-- Hidden addon messages between LooserPiml friends (never visible chat).
--
-- Who: only players on the explicit, mutual LooserPiml friends list
-- (Core/Friends.lua). Every outgoing message has a scope; Friends:Route
-- decides, at the moment it is really sent, which friends get it, and each
-- of them gets one WHISPER addon message. Whether anyone is grouped doesn't
-- matter. Incoming messages from anyone who isn't on the list are dropped
-- unread.
--
-- Wire format: AceSerializer -> LibDeflate (deflate + addon-channel encoding)
-- -> AceComm (chunking) -> ChatThrottleLib (throttling) ->
-- C_ChatInfo.SendAddonMessage with chat type WHISPER. Never PARTY, RAID,
-- INSTANCE_CHAT or GUILD (they reach players who aren't friends), never
-- Battle.net.
--
-- Envelope: { v = protocol, t = type, s = session, id = seq, d = data, late = reason }
--
-- Restrictions: during boss encounters (and other chat-lockdown states)
-- addon messages are blocked. Outgoing messages are then held in a queue and
-- flushed once sending is allowed again. If the client still refuses a send
-- (AceComm reports didSend == false), the message is held and retried, at
-- most MAX_ATTEMPTS times.
--
-- Usage from modules:
--   ns.Comm:RegisterHandler(owner, "TYPE", function(owner, data, sender, meta) end)
--   ns.Comm:Send("TYPE", data, { scope = "friends" | "handshake", prio, key, to, reply })
local _, ns = ...

local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local Comm = {}
ns:RegisterCore("Comm", Comm)
AceComm:Embed(Comm) -- Comm:RegisterComm, Comm:SendCommMessage

-- Prefixes are limited to 16 chars and must be registered
-- (C_ChatInfo.RegisterAddonMessagePrefix, done by RegisterComm), otherwise
-- the client never delivers them. The server throttles per prefix (about 10
-- messages burst, then 1/s), so keeping one prefix plus few chunks matters.
Comm.PREFIX = "LPiml"
Comm.PROTOCOL = 1              -- bump on incompatible envelope/payload changes
Comm.MAX_QUEUE = 50            -- held messages; oldest are dropped beyond this
Comm.MAX_AGE = 2 * 60 * 60     -- seconds a held message stays worth sending
Comm.MAX_ATTEMPTS = 5          -- sends per message before giving up
Comm.RETRY_INTERVAL = 5        -- seconds between flush attempts while holding
Comm.FLUSH_DELAY = 1           -- seconds to wait after a restriction lifts
Comm.SELFTEST = "SELFTEST"     -- /lp selftest ping, sent back by the friend as SELFTEST_ECHO
Comm.SELFTEST_ECHO = "SELFTEST_ECHO"
Comm.MAX_SEEN = 500            -- remembered message ids (duplicate filter)

-- Large messages travel as our own numbered parts, each a normal single
-- addon message, instead of AceComm's multi-part chunks. Seen on the Forever
-- beta (2026-10-20, two players): single messages arrived intact, but every
-- AceComm multi-part message (STATS with duels, the self-test) arrived
-- reassembled yet damaged ("bad compression"). Whether full 255-byte chunks
-- get cut, lost or reordered is TODO(verify in-game); smaller parts, sent a
-- little apart and joined only when all of them are there in order, avoid
-- all three. A part that never arrives is logged with what was missing.
-- Part text: "LPP<id>:<index>/<total>:<piece of the encoded message>"
Comm.MAX_SINGLE = 240          -- encoded messages up to this size go as they are
Comm.PART_SIZE = 200           -- bytes of the encoded message per part (+ ~16 header)
Comm.PART_INTERVAL = 0.2       -- seconds between two parts (all recipients together)
Comm.PART_TIMEOUT = 60         -- seconds an incomplete message is kept
Comm.MAX_PARTS = 64            -- parts per message (12 KB), more is refused
Comm.MAX_PARTIAL = 30          -- incomplete messages kept at once
local PART_PATTERN = "^LPP(%w+):(%d+)/(%d+):(.*)$"

local handlers = {} -- type -> array of { owner, fn }
local seq = 0
local seen, seenOrder = {}, {}

-- Random per-session id, so message ids stay unique across /reload.
Comm.session = math.random(1, 2147483646)

Comm.queue = {}

----------------------------------------------------------------------
-- Encoding
----------------------------------------------------------------------

-- Addon messages are at most 255 bytes and may not contain NUL bytes.
-- Compressing keeps most messages to a single chunk, which saves throttle
-- budget. Compressed data does contain NULs, so it is re-encoded for the
-- addon channel.
function Comm:Encode(envelope)
	local serialized = AceSerializer:Serialize(envelope)
	local compressed = LibDeflate:CompressDeflate(serialized)
	return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

function Comm:Decode(text)
	if type(text) ~= "string" then
		return nil, "not a string"
	end
	local compressed = LibDeflate:DecodeForWoWAddonChannel(text)
	if not compressed then
		return nil, "bad encoding"
	end
	local serialized = LibDeflate:DecompressDeflate(compressed)
	if not serialized then
		return nil, "bad compression"
	end
	local ok, envelope = AceSerializer:Deserialize(serialized)
	if not ok or type(envelope) ~= "table" then
		return nil, "bad serialization"
	end
	return envelope
end

local function nextId()
	seq = seq + 1
	return seq
end

----------------------------------------------------------------------
-- Handlers
----------------------------------------------------------------------

function Comm:RegisterHandler(owner, msgType, fn)
	assert(type(msgType) == "string" and type(fn) == "function", "RegisterHandler(owner, type, fn)")
	local list = handlers[msgType] or {}
	handlers[msgType] = list
	for _, entry in ipairs(list) do
		if entry.owner == owner then
			entry.fn = fn
			return
		end
	end
	list[#list + 1] = { owner = owner, fn = fn }
end

function Comm:UnregisterHandlers(owner)
	for msgType, list in pairs(handlers) do
		for i = #list, 1, -1 do
			if list[i].owner == owner then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			handlers[msgType] = nil
		end
	end
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

-- Returns true plus a reason ("encounter" or "lockdown") while addon
-- messages must not be sent. The encounter is checked first because it is
-- the more specific reason (receivers show "During the boss: ...").
-- Both signals are used because which one Forever actually raises during a
-- boss is TODO(verify in-game). InChatMessagingLockdown also covers
-- Mythic+/PvP and possibly whole dungeons ("communication-restricted maps").
function Comm:IsRestricted()
	if ns.Events:IsEncounterActive() then
		return true, "encounter"
	end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local locked = C_ChatInfo.InChatMessagingLockdown()
		-- Testing a secret boolean errors; IsSecret short-circuits first.
		if ns.IsSecret(locked) or locked then
			return true, "lockdown"
		end
	end
	return false
end

-- Sends a message to LooserPiml friends. Returns what happened:
--   "sent"     handed to AceComm/ChatThrottleLib
--   "queued"   held because sending is restricted right now
--   "nobody"   no friend may (or can) receive it right now
--   "loopback" test mode, delivered locally only
--   "dropped"  created in test mode, which has ended: never sent for real
-- Why our own queue on top of ChatThrottleLib's: CTL only retries the
-- AddonMessageThrottle result. Any other refusal (AddOnMessageLockdown during
-- a boss, TargetOffline, ...) is reported once and the message is dropped.
-- opts (all optional):
--   scope  who may get it (Friends.SCOPES), default "friends"
--   to     array of names: only these (still checked against the scope)
--   reply  answer to a friend who just wrote to us (see Friends.REPLY_WINDOW)
--   prio   ChatThrottleLib priority, default "NORMAL"
--   key    while held, a newer message with the same key replaces the older
--          one (e.g. stats snapshots: only the latest matters)
function Comm:Send(msgType, data, opts)
	opts = opts or {}
	local scope = opts.scope or "friends"
	assert(ns.Friends.SCOPES[scope], "unknown scope " .. tostring(scope))
	local entry = {
		t = msgType,
		d = data,
		id = nextId(),
		prio = opts.prio or "NORMAL",
		key = opts.key,
		scope = scope,
		to = opts.to,
		reply = opts.reply,
		-- Remembered, so a message held during a simulated boss can never go
		-- out for real after test mode was turned off.
		test = ns.TestMode:IsEnabled() or nil,
		queuedAt = time(),
		attempts = 0,
	}
	if self:IsRestricted() then
		return self:Hold(entry)
	end
	if entry.key then
		self:DropHeld(entry.key) -- superseded: an older snapshot must not arrive after this one
	end
	return self:Transmit(entry)
end

function Comm:DropHeld(key)
	for i = #self.queue, 1, -1 do
		if self.queue[i].key == key then
			table.remove(self.queue, i)
		end
	end
end

local partSeq = 0
local nextPartAt = 0

-- Hands an encoded message to AceComm for one whisper target: as it is if
-- it fits MAX_SINGLE, otherwise as numbered parts PART_INTERVAL apart.
-- done(allSent) once every part was handed to the client. AceComm calls
-- back with (arg, bytesSent, bytesTotal, didSend); didSend is CTL's boolean
-- (nil on old AceComm versions), only false means the client refused.
-- scope: a part still due is skipped if the friend may no longer get it
-- (removed meanwhile) or test mode started. Returns the number of parts.
function Comm:SendText(text, target, prio, done, scope)
	if #text <= self.MAX_SINGLE then
		self:SendCommMessage(self.PREFIX, text, "WHISPER", target, prio, function(_, _, _, didSend)
			if done then
				done(didSend ~= false)
			end
		end)
		return 1
	end
	partSeq = partSeq + 1
	local id = string.format("%x%x", self.session % 4096, partSeq)
	local total = math.ceil(#text / self.PART_SIZE)
	local remaining, allSent = total, true
	local now = GetTime()
	local function partDone(didSend)
		if didSend == false then
			allSent = false
		end
		remaining = remaining - 1
		if remaining == 0 and done then
			done(allSent)
		end
	end
	for i = 1, total do
		local part = string.format("LPP%s:%d/%d:", id, i, total) .. text:sub((i - 1) * self.PART_SIZE + 1, i * self.PART_SIZE)
		local at = math.max(now, nextPartAt)
		nextPartAt = at + self.PART_INTERVAL
		C_Timer.After(at - now, function()
			local full = ns.Roster:Normalize(target)
			if ns.TestMode:IsEnabled() or not (full and ns.Friends:Allowed(full, scope or "friends")) then
				partDone(false)
				return
			end
			self:SendCommMessage(self.PREFIX, part, "WHISPER", target, prio, function(_, _, _, didSend)
				partDone(didSend)
			end)
		end)
	end
	return total
end

-- Messages created in test mode never leave the client, even when they
-- were held and test mode is off by the time they would be flushed.
function Comm:DropTestMessages()
	for i = #self.queue, 1, -1 do
		if self.queue[i].test then
			table.remove(self.queue, i)
		end
	end
end

function Comm:Transmit(entry)
	if entry.test and not ns.TestMode:IsEnabled() then
		ns.Log:Debug("Dropped a %s message from test mode", entry.t)
		return "dropped"
	end
	local envelope = {
		v = self.PROTOCOL,
		t = entry.t,
		s = self.session,
		id = entry.id,
		d = entry.d,
		late = entry.late,
	}
	local text = self:Encode(envelope)

	if ns.TestMode:IsEnabled() then
		-- Nothing leaves the client in test mode.
		self:Receive(text, ns.Roster:GetPlayerName(), "LOOPBACK", true)
		return "loopback"
	end

	-- Resolved now, not when queued: the friends list or who is online may
	-- have changed while the message was held.
	local recipients = ns.Friends:Route(entry.scope, entry.to, entry.reply)
	if #recipients == 0 then
		return "nobody"
	end
	entry.attempts = entry.attempts + 1
	entry.failed = false
	-- If any part is refused, receivers never complete the message, and we
	-- resend all of it (their duplicate filter drops a copy that did arrive).
	local function done(allSent)
		if not allSent and not entry.failed then
			entry.failed = true
			Comm:OnSendFailed(entry)
		end
	end
	for _, full in ipairs(recipients) do
		self:SendText(text, ns.Friends:GetShortTarget(full), entry.prio, done, entry.scope)
	end
	-- Lets senders rate-limit by actual transmissions, including messages
	-- that were held and flushed later.
	ns.Events:Fire("LP_COMM_SENT", entry.t)
	return "sent"
end

function Comm:Hold(entry, atFront)
	local _, reason = self:IsRestricted()
	entry.late = entry.late or reason
	if entry.key then
		for i = #self.queue, 1, -1 do
			local other = self.queue[i]
			if other.key == entry.key then
				if other.id > entry.id then
					return "queued" -- a newer version is already waiting (failed retry of an old one)
				end
				table.remove(self.queue, i)
			end
		end
	end
	if atFront then
		table.insert(self.queue, 1, entry)
	else
		self.queue[#self.queue + 1] = entry
	end
	while #self.queue > self.MAX_QUEUE do
		local dropped = table.remove(self.queue, 1)
		ns.Log:Warn("Outgoing queue full, dropped a %s message", dropped.t)
	end
	ns.Log:Debug("Holding %s message (%s), %d queued", entry.t, tostring(reason or "retry"), #self.queue)
	self:StartRetryTimer()
	return "queued"
end

function Comm:OnSendFailed(entry)
	if entry.attempts >= self.MAX_ATTEMPTS then
		ns.Log:Warn("Gave up sending a %s message after %d attempts", entry.t, entry.attempts)
		return
	end
	ns.Log:Debug("Send of %s refused by the client (attempt %d), will retry", entry.t, entry.attempts)
	self:Hold(entry, true)
end

function Comm:Flush()
	if #self.queue == 0 then
		self:StopRetryTimer()
		return 0
	end
	if self:IsRestricted() then
		return 0
	end
	local pending = self.queue
	self.queue = {}
	local now = time()
	local sent = 0
	for _, entry in ipairs(pending) do
		if now - entry.queuedAt > self.MAX_AGE then
			ns.Log:Debug("Dropped a stale %s message", entry.t)
		else
			local status = self:Transmit(entry)
			if status == "sent" or status == "loopback" then
				sent = sent + 1
			end
		end
	end
	if #self.queue == 0 then
		self:StopRetryTimer()
	end
	ns.Log:Debug("Flushed %d held message(s)", sent)
	return sent
end

function Comm:ScheduleFlush(delay)
	C_Timer.After(delay or self.FLUSH_DELAY, function()
		self:Flush()
	end)
end

function Comm:StartRetryTimer()
	if not self.retryTicker then
		self.retryTicker = C_Timer.NewTicker(self.RETRY_INTERVAL, function()
			self:Flush()
		end)
	end
end

function Comm:StopRetryTimer()
	if self.retryTicker then
		self.retryTicker:Cancel()
		self.retryTicker = nil
	end
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

local function isDuplicate(sender, envelope)
	if type(envelope.id) ~= "number" then
		return false
	end
	local key = sender .. ":" .. tostring(envelope.s) .. ":" .. envelope.id
	if seen[key] then
		return true
	end
	seen[key] = true
	seenOrder[#seenOrder + 1] = key
	if #seenOrder > Comm.MAX_SEEN then
		seen[table.remove(seenOrder, 1)] = nil
	end
	return false
end

Comm.partial = {} -- sender .. "/" .. id -> { parts = {}, count, total, at, sender }
Comm.warned = {}  -- friend .. "|" .. kind -> true (one visible hint per session)

-- A visible chat line (no debug mode needed) the first time a friend's
-- message arrives damaged ("damaged") or incomplete ("parts") this
-- session. Transport on the live servers couldn't be fully tested before
-- launch; this way friends notice on the first evening and know what to
-- run, instead of just seeing empty tabs.
function Comm:WarnDelivery(full, kind)
	local id = full .. "|" .. kind
	if self.warned[id] then
		return
	end
	self.warned[id] = true
	ns.Log:Print(kind == "parts" and ns.L.COMM_INCOMPLETE or ns.L.COMM_DAMAGED, ns.Roster:ColorName(full))
end

-- Drops incomplete messages older than PART_TIMEOUT, saying what was
-- missing (the in-game diagnosis for lost parts).
function Comm:PrunePartial(now)
	for key, msg in pairs(self.partial) do
		if now - msg.at > self.PART_TIMEOUT then
			local missing = {}
			for i = 1, msg.total do
				if not msg.parts[i] then
					missing[#missing + 1] = i
				end
			end
			ns.Log:Debug("Incomplete message from %s: %d of %d parts arrived, missing %s", msg.sender, msg.count, msg.total, table.concat(missing, ","))
			self.partial[key] = nil
			self:WarnDelivery(msg.sender, "parts")
		end
	end
end

-- One of our parts (see SendText). Returns the whole encoded message once
-- every part is there, nil while waiting. Only listed friends' parts are
-- kept at all (the same rule as Receive, before anything is stored).
function Comm:AddPart(text, sender)
	local id, index, total, piece = text:match(PART_PATTERN)
	if not id then
		return nil, false
	end
	index, total = tonumber(index), tonumber(total)
	local full = type(sender) == "string" and not ns.IsSecret(sender) and ns.Roster:Normalize(sender)
	if not full or not ns.Friends:IsListed(full) or #id > 16
		or not index or not total or total < 2 or total > self.MAX_PARTS or index < 1 or index > total then
		return nil, true
	end
	local now = GetTime()
	self:PrunePartial(now)
	local key = full .. "/" .. id
	local msg = self.partial[key]
	if not msg then
		local count = 0
		for _ in pairs(self.partial) do
			count = count + 1
		end
		if count >= self.MAX_PARTIAL then
			ns.Log:Debug("Too many incomplete messages, dropped a part from %s", full)
			return nil, true
		end
		msg = { parts = {}, count = 0, total = total, at = now, sender = full }
		self.partial[key] = msg
		-- Also cleaned up (and logged) when no further part ever comes.
		C_Timer.After(self.PART_TIMEOUT + 1, function()
			self:PrunePartial(GetTime())
		end)
	end
	if msg.total ~= total or msg.parts[index] then
		return nil, true -- inconsistent or a duplicate part
	end
	msg.parts[index] = piece
	msg.count = msg.count + 1
	if msg.count < total then
		return nil, true
	end
	self.partial[key] = nil
	return table.concat(msg.parts, "", 1, total), true
end

-- AceComm callback. AceComm still reassembles its own multi-part chunks
-- (older LooserPiml versions send those); our parts come as single
-- messages and are joined here first.
function Comm:OnCommReceived(prefix, text, distribution, sender)
	if prefix ~= self.PREFIX then
		return
	end
	if type(text) == "string" and text:sub(1, 3) == "LPP" then
		local whole, isPart = self:AddPart(text, sender)
		if isPart then
			if whole then
				self:Receive(whole, sender, distribution, false)
			end
			return
		end
	end
	self:Receive(text, sender, distribution, false)
end

function Comm:Receive(text, sender, distribution, isTest)
	if type(sender) ~= "string" or ns.IsSecret(sender) then
		return
	end
	-- AceComm Ambiguates senders: "Name" for our realm, "Name-Realm" otherwise.
	-- Normalize gives one key for both.
	local fullSender = ns.Roster:Normalize(sender)
	if not fullSender then
		return
	end
	local fromSelf = ns.Roster:IsPlayer(fullSender)
	-- Mutual opt-in: whoever isn't on our LooserPiml friends list is
	-- ignored, before the message is even decoded. Test-mode loopback and
	-- simulated fake members never touch the network.
	if not isTest and not fromSelf then
		if not ns.Friends:IsListed(fullSender) then
			ns.Log:Debug("Dropped a message from %s (not on your LooserPiml friends list)", fullSender)
			return
		end
		ns.Friends:NoteHeard(fullSender)
	end
	local envelope, err = self:Decode(text)
	if not envelope then
		ns.Log:Debug("Unreadable message from %s (%s)", fullSender, err)
		if not isTest and not fromSelf then
			self:WarnDelivery(fullSender, "damaged")
		end
		return
	end
	if type(envelope.t) ~= "string" or type(envelope.v) ~= "number" then
		return
	end

	if fromSelf then
		-- Only test-mode loopback hands our own messages back (whispers are
		-- never echoed). Own events were already displayed locally.
		ns.Log:Debug("%s own %s message", isTest and "[test] Looped back" or "Ignored echo of", envelope.t)
		return
	end
	if envelope.v ~= self.PROTOCOL and envelope.t ~= "HELLO" then
		ns.Log:Debug("Ignored %s from %s: protocol %s, ours %d", envelope.t, fullSender, tostring(envelope.v), self.PROTOCOL)
		return
	end
	if isDuplicate(fullSender, envelope) then
		return
	end

	local list = handlers[envelope.t]
	if not list then
		ns.Log:Debug("No handler for %s from %s", envelope.t, fullSender)
		return
	end
	local meta = {
		distribution = distribution,
		test = isTest == true,
		late = envelope.late,
		protocol = envelope.v,
	}
	for _, entry in ipairs(list) do
		ns.SafeCall(entry.fn, entry.owner, envelope.d, fullSender, meta)
	end
end

----------------------------------------------------------------------
-- Test helpers
----------------------------------------------------------------------

-- Test mode: pretend `sender` sent this message. Runs the real
-- encode -> decode -> dispatch path, without touching the network.
local simSession = math.random(1, 2147483646)
function Comm:SimulateReceive(sender, msgType, data, late)
	local envelope = { v = self.PROTOCOL, t = msgType, s = simSession, id = nextId(), d = data, late = late }
	self:Receive(self:Encode(envelope), sender, "LOOPBACK", true)
end

-- /lp selftest: a real multi-part addon message whispered to one
-- connected friend, whose client sends it back (TestMode's echo handler).
-- Bypasses the hold queue on purpose (the caller skips it in test mode and
-- while restricted). Returns nil unless `target` is a connected friend.
-- onResult(didSend) is called once all parts were handed to the client.
-- Why not a whisper to ourselves: on Forever the server rejects it ("No
-- player named X is currently playing").
function Comm:SendSelfTest(data, target, onResult)
	if not ns.Friends:IsConnected(target) then
		return nil
	end
	local envelope = { v = self.PROTOCOL, t = self.SELFTEST, s = self.session, id = nextId(), d = data }
	local text = self:Encode(envelope)
	local parts = self:SendText(text, ns.Friends:GetShortTarget(target), "NORMAL", onResult)
	return #text, parts
end

-- How many addon messages an encoded message of this size becomes.
function Comm:CountParts(bytes)
	return bytes <= self.MAX_SINGLE and 1 or math.ceil(bytes / self.PART_SIZE)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Comm:OnInitialize()
	self:RegisterComm(self.PREFIX, "OnCommReceived")
end

function Comm:OnEnable()
	ns.Events:Register(self, "LP_ENCOUNTER_END", function()
		self:ScheduleFlush()
	end)
	-- Payload (type, state). Documented to fire before a restriction becomes
	-- active and after it was lifted, so Inactive means "may send again".
	-- FLUSH_DELAY gives the client a moment anyway; Flush re-checks.
	ns.Events:Register(self, "ADDON_RESTRICTION_STATE_CHANGED", function(_, _, _, state)
		local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
		if not ns.IsSecret(state) and state == inactive then
			self:ScheduleFlush()
		end
	end)
	-- Leaving an instance can lift a lockdown without any encounter event.
	ns.Events:Register(self, "PLAYER_ENTERING_WORLD", function()
		self:ScheduleFlush()
	end)
end
