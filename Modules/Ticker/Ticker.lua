-- Ticker: each client detects only its own player's events, shows them
-- locally and broadcasts them; receivers count and display them.
--
-- Events (MVP): level up, death (with a "drowned" variant), entering and
-- leaving a dungeon or raid.
--
-- Payload of a TICK message (short keys, every field optional except k):
--   k   kind: "death" | "levelup" | "enter" | "leave"
--   c   sender's class file name ("WARRIOR"), for name coloring
--   lvl new level (levelup)
--   dr  true if drowned (death)
--   z   zone name (death)
--   i   instance name, it = "party" | "raid" (enter/leave)
local _, ns = ...
local L = ns.L

local Ticker = ns:NewModule("Ticker")

Ticker.MSG = "TICK"
Ticker.KINDS = { death = true, levelup = true, enter = true, leave = true }
Ticker.REENTER_GRACE = 10 * 60   -- seconds: re-entering the same instance stays quiet (corpse runs)
Ticker.DROWN_TOLERANCE_MS = 1000 -- breath left (ms) at death that still counts as drowned
Ticker.BREATH_STOP_WINDOW = 1.5  -- seconds: MIRROR_TIMER_STOP may arrive just before PLAYER_DEAD
Ticker.MAX_TEXT = 64             -- max length of names coming from other clients

Ticker.defaults = {
	stats = {},     -- all-time stats, see Stats.lua
	chatLog = true, -- also print each event as a local chat line
}

local function notSecret(value)
	if ns.IsSecret(value) then
		return nil
	end
	return value
end

function Ticker:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, self.defaults)
	ns.Slash:Register("stats", function()
		if self:IsEnabled() then
			self.Stats:PrintReport()
		end
	end, "", L.HELP_STATS)
end

function Ticker:OnEnable()
	ns.Events:Register(self, "PLAYER_LEVEL_UP")
	ns.Events:Register(self, "PLAYER_DEAD")
	ns.Events:Register(self, "PLAYER_ALIVE")
	ns.Events:Register(self, "PLAYER_UNGHOST")
	ns.Events:Register(self, "MIRROR_TIMER_START")
	ns.Events:Register(self, "MIRROR_TIMER_PAUSE")
	ns.Events:Register(self, "MIRROR_TIMER_STOP")
	ns.Events:Register(self, "PLAYER_ENTERING_WORLD")
	ns.Events:Register(self, "LP_ENCOUNTER_START", function()
		self.Display:OnEncounterStart()
	end)
	ns.Events:Register(self, "LP_ENCOUNTER_END", function()
		self.Display:OnEncounterEnd()
	end)
	ns.Comm:RegisterHandler(self, self.MSG, self.OnTick)
	ns.TestMode:RegisterSim(self, { "death", "drown", "levelup", "enter", "leave" }, self.Simulate)

	self.dead = self:IsPlayerDeadOrGhost()
	self.instance = self:GetCurrentInstance()
	self.instanceKnown = true
end

----------------------------------------------------------------------
-- Own events
----------------------------------------------------------------------

-- Show locally, count, broadcast. isTest marks simulated events (never
-- counted in all-time stats).
function Ticker:OnOwnEvent(kind, data, isTest)
	data = data or {}
	data.k = kind
	data.c = data.c or ns.Roster:GetPlayerClass()
	local me = ns.Roster:GetPlayerName()
	self.Stats:Record(me, data, isTest)
	self.Display:ShowEvent(me, data, { test = isTest })
	return ns.Comm:Send(self.MSG, data)
end

function Ticker:PLAYER_LEVEL_UP(_, level)
	level = notSecret(level)
	if type(level) ~= "number" then
		level = nil
	end
	self:OnOwnEvent("levelup", { lvl = level })
end

function Ticker:IsPlayerDeadOrGhost()
	local dead = UnitIsDeadOrGhost("player")
	if ns.IsSecret(dead) then
		return false
	end
	return dead and true or false
end

-- PLAYER_DEAD isn't documented to fire exactly once per death (e.g. a
-- /reload while dead), and counting twice would spoil the stats. So we only
-- count again after PLAYER_ALIVE/PLAYER_UNGHOST. TODO(verify in-game).
function Ticker:PLAYER_DEAD()
	if self.dead then
		return -- already counted this death
	end
	self.dead = true
	local zone = GetRealZoneText and notSecret(GetRealZoneText())
	self:OnOwnEvent("death", {
		dr = self:WasDrowning() or nil,
		z = zone ~= "" and zone or nil,
	})
end

-- PLAYER_ALIVE fires on resurrection and also when releasing to a ghost.
function Ticker:PLAYER_ALIVE()
	if not self:IsPlayerDeadOrGhost() then
		self.dead = false
	end
end

function Ticker:PLAYER_UNGHOST()
	self.dead = false
end

----------------------------------------------------------------------
-- Drowning: was the breath timer (nearly) empty when we died?
----------------------------------------------------------------------
-- Uses only the MIRROR_TIMER_* payload and GetMirrorTimerProgress. If any of
-- these values is secret, drowning detection is skipped (plain death).
--
-- Why not the combat log: COMBAT_LOG_EVENT_UNFILTERED can't be registered
-- under Midnight rules, so there is no "killed by X". The breath bar is a
-- "mirror timer". When it hits zero you don't die at once; you take damage
-- every few seconds until dead. So "drowned" means the timer was at or past
-- zero at death, not exactly zero. The order of MIRROR_TIMER_STOP and
-- PLAYER_DEAD at that moment is TODO(verify in-game), hence the stop window.

-- Payload: value/maxValue in milliseconds; scale = change per second (-1 =
-- draining in real time, positive = refilling after surfacing); paused is a
-- number (0/1) per the docs, boolean on some clients.
function Ticker:MIRROR_TIMER_START(_, timerName, value, _, scale, paused)
	if ns.IsSecret(timerName) or timerName ~= "BREATH" then
		return
	end
	if ns.IsSecret(value) or ns.IsSecret(scale) or ns.IsSecret(paused)
		or type(value) ~= "number" or type(scale) ~= "number" then
		self.breath = nil
		ns.Log:Debug("Breath timer values unavailable, drowning detection off")
		return
	end
	self.breath = {
		value = value,
		scale = scale,
		paused = paused == true or (type(paused) == "number" and paused > 0),
		startedAt = GetTime(),
	}
	self.breathStop = nil
end

function Ticker:MIRROR_TIMER_PAUSE(_, timerName, paused)
	if ns.IsSecret(timerName) or timerName ~= "BREATH" or not self.breath or ns.IsSecret(paused) then
		return
	end
	local isPaused = paused == true or (type(paused) == "number" and paused > 0)
	-- Freeze or restart the countdown from the current remaining value.
	self.breath.value = self:BreathRemaining() or self.breath.value
	self.breath.startedAt = GetTime()
	self.breath.paused = isPaused
end

function Ticker:MIRROR_TIMER_STOP(_, timerName)
	if ns.IsSecret(timerName) or timerName ~= "BREATH" then
		return
	end
	if self.breath then
		self.breathStop = { at = GetTime(), remaining = self:BreathRemaining(), scale = self.breath.scale }
	end
	self.breath = nil
end

-- Milliseconds of breath left, or nil if unknown.
function Ticker:BreathRemaining()
	local breath = self.breath
	if not breath then
		return nil
	end
	if GetMirrorTimerProgress then
		local progress = GetMirrorTimerProgress("BREATH")
		if type(progress) == "number" and not ns.IsSecret(progress) and progress > 0 then
			return progress
		end
		-- The API returns 0 for "timer inactive", so 0 is ambiguous with
		-- "empty". Fall back to the start payload.
	end
	if breath.paused then
		return breath.value
	end
	return breath.value + breath.scale * 1000 * (GetTime() - breath.startedAt)
end

function Ticker:WasDrowning()
	local remaining, scale
	if self.breath then
		remaining, scale = self:BreathRemaining(), self.breath.scale
	elseif self.breathStop and GetTime() - self.breathStop.at <= self.BREATH_STOP_WINDOW then
		remaining, scale = self.breathStop.remaining, self.breathStop.scale
	end
	if remaining == nil or scale == nil or scale >= 0 then
		return false -- no timer, or breath was refilling
	end
	return remaining <= self.DROWN_TOLERANCE_MS
end

----------------------------------------------------------------------
-- Dungeon / raid enter and leave
----------------------------------------------------------------------

-- instanceType: "party" = dungeon, "raid", "pvp", "arena", "scenario",
-- "none". Instance names are localized, but instanceID is stable, so the ID
-- is the comparison key (name only as a fallback).
function Ticker:GetCurrentInstance()
	local inInstance, instanceType = IsInInstance()
	if ns.IsSecret(inInstance) or ns.IsSecret(instanceType) then
		return nil
	end
	if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
		return nil
	end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	return { name = notSecret(name), type = instanceType, id = notSecret(instanceID) or notSecret(name) }
end

-- PLAYER_ENTERING_WORLD fires after every loading screen, and entering or
-- leaving an instance always has one, so there's no polling. The flags tell
-- us when the loading screen came from a login or /reload rather than a move.
function Ticker:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
	local before, now = self.instance, self:GetCurrentInstance()
	self.instance = now
	if isInitialLogin or isReloadingUi or not self.instanceKnown then
		self.instanceKnown = true -- baseline only, nothing happened
		return
	end
	local changed = (before and now and before.id ~= now.id) or (before == nil) ~= (now == nil)
	if not changed then
		return
	end
	if before then
		self:OnLeftInstance(before)
	end
	if now then
		self:OnEnteredInstance(now)
	end
end

function Ticker:OnLeftInstance(instance)
	self.lastLeft = { id = instance.id, at = GetTime() }
	if self:IsPlayerDeadOrGhost() then
		return -- released after a wipe; the corpse run stays quiet
	end
	self:OnOwnEvent("leave", { i = instance.name, it = instance.type })
end

function Ticker:OnEnteredInstance(instance)
	local last = self.lastLeft
	if last and last.id == instance.id and GetTime() - last.at < self.REENTER_GRACE then
		return
	end
	self:OnOwnEvent("enter", { i = instance.name, it = instance.type })
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

local function cleanText(value, maxLength)
	if type(value) ~= "string" or value == "" then
		return nil
	end
	-- "|" starts WoW escape sequences (colors, textures, links): neutralize.
	return (value:sub(1, maxLength):gsub("|", "||"))
end

-- Copies only known fields with the expected types. The payload comes from
-- another client (possibly an older or buggy version), so trust nothing.
function Ticker:Sanitize(data)
	if type(data) ~= "table" or not self.KINDS[data.k] then
		return nil
	end
	local clean = { k = data.k }
	if type(data.c) == "string" and data.c:match("^[A-Z]+$") and #data.c <= 20 then
		clean.c = data.c
	end
	if type(data.lvl) == "number" and data.lvl >= 1 and data.lvl <= 1000 then
		clean.lvl = math.floor(data.lvl)
	end
	clean.dr = data.dr == true or nil
	clean.z = cleanText(data.z, self.MAX_TEXT)
	clean.i = cleanText(data.i, self.MAX_TEXT)
	if data.it == "party" or data.it == "raid" then
		clean.it = data.it
	end
	return clean
end

function Ticker:OnTick(data, sender, meta)
	local event = self:Sanitize(data)
	if not event then
		ns.Log:Debug("Ignored malformed TICK from %s", tostring(sender))
		return
	end
	self.Stats:Record(sender, event, meta.test)
	self.Display:ShowEvent(sender, event, { late = meta.late, test = meta.test })
end

----------------------------------------------------------------------
-- Test mode
----------------------------------------------------------------------

-- name == nil simulates the player (local display + loopback broadcast);
-- otherwise a message "from" that (fake) group member is received.
function Ticker:Simulate(kind, name)
	local data
	if kind == "death" then
		data = { k = "death", z = GetRealZoneText and notSecret(GetRealZoneText()) or nil }
	elseif kind == "drown" then
		data = { k = "death", dr = true }
	elseif kind == "levelup" then
		local level = notSecret(UnitLevel("player"))
		data = { k = "levelup", lvl = name and math.random(2, 60) or (type(level) == "number" and level + 1 or nil) }
	elseif kind == "enter" or kind == "leave" then
		data = { k = kind, i = L.SIM_DUNGEON, it = "party" }
	else
		return
	end
	if not name then
		self:OnOwnEvent(data.k, data, true)
		return
	end
	local member = ns.Roster:GetMember(name)
	data.c = member and member.class
	ns.Comm:SimulateReceive(name, self.MSG, data)
end
