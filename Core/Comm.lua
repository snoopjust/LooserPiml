-- Hidden addon messages between group members (never visible chat).
--
-- Wire format: AceSerializer -> LibDeflate (deflate + addon-channel encoding)
-- -> AceComm (chunking) -> ChatThrottleLib (throttling) ->
-- C_ChatInfo.SendAddonMessage on PARTY/RAID (INSTANCE_CHAT in finder groups).
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
--   ns.Comm:Send("TYPE", data)
local _, ns = ...

local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local Comm = {}
ns:RegisterCore("Comm", Comm)
AceComm:Embed(Comm) -- Comm:RegisterComm, Comm:SendCommMessage

Comm.PREFIX = "LPiml"          -- registered addon-message prefix (max 16 chars)
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
function Comm:IsRestricted()
	if ns.Events:IsEncounterActive() then
		return true, "encounter"
	end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local locked = C_ChatInfo.InChatMessagingLockdown()
		if ns.IsSecret(locked) or locked then
			return true, "lockdown"
		end
	end
	return false
end

-- Sends a message to the group. Returns what happened:
--   "sent"     handed to AceComm/ChatThrottleLib
--   "queued"   held because sending is restricted right now
--   "solo"     not in a group, nobody to tell
--   "loopback" test mode, delivered locally only
function Comm:Send(msgType, data, prio)
	local entry = {
		t = msgType,
		d = data,
		id = nextId(),
		prio = prio or "NORMAL",
		queuedAt = time(),
		attempts = 0,
	}
	if self:IsRestricted() then
		return self:Hold(entry)
	end
	return self:Transmit(entry)
end

local function onChunkSent(entry, _, _, didSend)
	-- AceComm passes (arg, bytesSent, bytesTotal, didSend) per chunk.
	-- didSend is nil on old AceComm versions; only false means failure.
	if didSend == false and not entry.failed then
		entry.failed = true
		Comm:OnSendFailed(entry)
	end
end

function Comm:Transmit(entry)
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

	local channel = ns.Roster:GetChannel()
	if not channel then
		return "solo"
	end
	entry.attempts = entry.attempts + 1
	entry.failed = false
	self:SendCommMessage(self.PREFIX, text, channel, nil, entry.prio, onChunkSent, entry)
	return "sent"
end

function Comm:Hold(entry, atFront)
	local _, reason = self:IsRestricted()
	entry.late = entry.late or reason
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
	local envelope, err = self:Decode(text)
	if not envelope then
		ns.Log:Debug("Unreadable message from %s (%s)", sender, err)
		return
	end
	if type(envelope.t) ~= "string" or type(envelope.v) ~= "number" then
		return
	end

	local fullSender = ns.Roster:Normalize(sender)
	if ns.Roster:IsPlayer(fullSender) and envelope.t ~= self.SELFTEST then
		-- Own events are displayed locally; group channels echo them back.
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

-- /lp selftest: a real addon message, whispered to ourselves. Bypasses
-- test-mode loopback and the hold queue on purpose.
-- onResult(didSend) is called once all chunks were handed to the client.
function Comm:SendSelfTest(data, onResult)
	local envelope = { v = self.PROTOCOL, t = self.SELFTEST, s = self.session, id = nextId(), d = data }
	local text = self:Encode(envelope)
	local target = UnitName("player")
	local allSent = true
	self:SendCommMessage(self.PREFIX, text, "WHISPER", target, "NORMAL", function(_, sent, total, didSend)
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
	ns.Events:Register(self, "ADDON_RESTRICTION_STATE_CHANGED", function(_, _, _, state)
		local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
		if not ns.IsSecret(state) and state == inactive then
			self:ScheduleFlush()
		end
	end)
	ns.Events:Register(self, "PLAYER_ENTERING_WORLD", function()
		self:ScheduleFlush()
	end)
end
