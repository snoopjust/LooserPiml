-- Hidden addon messages between LooserPiml friends (never visible chat).
--
-- Who: only players on the explicit, mutual LooserPiml friends list
-- (Core/Friends.lua). Every outgoing message has a scope; Friends:Route
-- decides, at the moment it is really sent, between the group channel
-- (only if every other group member may receive it) and individual
-- whispers to online friends. Incoming messages from anyone who isn't on
-- the list are dropped unread.
--
-- Wire format: AceSerializer -> LibDeflate (deflate + addon-channel encoding)
-- -> AceComm (chunking) -> ChatThrottleLib (throttling) ->
-- C_ChatInfo.SendAddonMessage on PARTY/RAID (INSTANCE_CHAT in finder
-- groups) or WHISPER. Never GUILD, never Battle.net.
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
--   ns.Comm:Send("TYPE", data, { scope = "group" | "friends" | "handshake", prio, key, to, reply })
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
Comm.SELFTEST = "SELFTEST"     -- the only type accepted from ourselves
Comm.MAX_SEEN = 500            -- remembered message ids (duplicate filter)

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
-- a boss, NotInGroup, ...) is reported once and the message is dropped.
-- opts (all optional):
--   scope  who may get it (Friends.SCOPES), default "group"
--   to     array of names: only these (still checked against the scope)
--   reply  answer to a friend who just wrote to us (see Friends.REPLY_WINDOW)
--   prio   ChatThrottleLib priority, default "NORMAL"
--   key    while held, a newer message with the same key replaces the older
--          one (e.g. stats snapshots: only the latest matters)
function Comm:Send(msgType, data, opts)
	opts = opts or {}
	local scope = opts.scope or "group"
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

local function onChunkSent(entry, _, _, didSend)
	-- AceComm passes (arg, bytesSent, bytesTotal, didSend) per chunk.
	-- didSend is CTL's boolean, not the Enum.SendAddonMessageResult code, so
	-- we can't tell a lockdown from other refusals here. It is nil on old
	-- AceComm versions; only false means failure. If one chunk of a multi-part
	-- message fails, receivers discard the incomplete message, and we resend
	-- all of it (their duplicate filter drops any copy that did arrive).
	if didSend == false and not entry.failed then
		entry.failed = true
		Comm:OnSendFailed(entry)
	end
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

	-- Resolved now, not when queued: the group, the friends list or who is
	-- online may have changed while the message was held.
	local channel, whispers = ns.Friends:Route(entry.scope, entry.to, entry.reply)
	if not channel and #whispers == 0 then
		return "nobody"
	end
	entry.attempts = entry.attempts + 1
	entry.failed = false
	if channel then
		self:SendCommMessage(self.PREFIX, text, channel, nil, entry.prio, onChunkSent, entry)
	end
	for _, full in ipairs(whispers) do
		self:SendCommMessage(self.PREFIX, text, "WHISPER", ns.Friends:GetShortTarget(full), entry.prio, onChunkSent, entry)
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

-- AceComm callback
function Comm:OnCommReceived(prefix, text, distribution, sender)
	if prefix == self.PREFIX then
		self:Receive(text, sender, distribution, false)
	end
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
		return
	end
	if type(envelope.t) ~= "string" or type(envelope.v) ~= "number" then
		return
	end

	if fromSelf and envelope.t ~= self.SELFTEST then
		-- The server delivers PARTY/RAID addon messages to the sender too.
		-- Own events were already displayed locally when they happened.
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

-- /lp selftest: a real addon message on the group channel, which the server
-- echoes back to us. Bypasses the hold queue on purpose (the caller skips
-- it in test mode and while restricted).
-- Returns nil plus "solo" when not in a group, or "strangers" when someone
-- in the group isn't on the friends list: the group channel would reach
-- them, so there is no real-transport test then.
-- onResult(didSend) is called once all chunks were handed to the client.
-- Why not a whisper to ourselves: on Forever the server rejects it ("No
-- player named X is currently playing"), so solo there is no real-transport
-- test. Friends' clients ignore SELFTEST messages (no handler registered).
function Comm:SendSelfTest(data, onResult)
	local channel = ns.Roster:GetChannel()
	if not channel then
		return nil, "solo"
	end
	if not ns.Friends:CanUseGroupChannel("handshake") then
		return nil, "strangers"
	end
	local envelope = { v = self.PROTOCOL, t = self.SELFTEST, s = self.session, id = nextId(), d = data }
	local text = self:Encode(envelope)
	local allSent = true
	self:SendCommMessage(self.PREFIX, text, channel, nil, "NORMAL", function(_, sent, total, didSend)
		if didSend == false then
			allSent = false
		end
		if sent >= total and onResult then
			onResult(allSent)
		end
	end)
	-- AceComm splits into chunks of up to 254 bytes (255 for single messages)
	local chunks = #text <= 255 and 1 or math.ceil(#text / 254)
	return #text, chunks
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
