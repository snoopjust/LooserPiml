-- Detects what happens to the player and fires internal messages that any
-- module can use (Ticker announces them, Stats records them):
--
--   LP_PLAYER_DEAD(info)       info = { drowned, zone, level, inInstance,
--                                       instanceName, instanceType, duringEncounter }
--   LP_PLAYER_LEVEL_UP(info)   info = { level }
--   LP_INSTANCE_ENTER(info)    info = { name, type, id }   any instance type
--   LP_INSTANCE_LEAVE(info)    info = { name, type, id, dead }
--
-- Only the own character is observed. Simulations (test mode) never pass
-- through here, so nothing simulated ends up in recorded stats.
local _, ns = ...

local PlayerEvents = {}
ns:RegisterCore("PlayerEvents", PlayerEvents)

PlayerEvents.REENTER_GRACE = 10 * 60   -- seconds: re-entering the same instance stays quiet (corpse runs)
PlayerEvents.DROWN_TOLERANCE_MS = 1000 -- breath left (ms) at death that still counts as drowned
PlayerEvents.BREATH_STOP_WINDOW = 1.5  -- seconds: MIRROR_TIMER_STOP may arrive just before PLAYER_DEAD

local function notSecret(value)
	if ns.IsSecret(value) then
		return nil
	end
	return value
end
PlayerEvents.NotSecret = notSecret

----------------------------------------------------------------------
-- Context helpers (also used by Stats for its log records)
----------------------------------------------------------------------

function PlayerEvents:IsPlayerDeadOrGhost()
	local dead = UnitIsDeadOrGhost("player")
	if ns.IsSecret(dead) then
		return false
	end
	return dead and true or false
end

function PlayerEvents:GetZone()
	local zone = GetRealZoneText and notSecret(GetRealZoneText())
	if zone == "" then
		return nil
	end
	return zone
end

function PlayerEvents:GetLevel()
	local level = notSecret(UnitLevel("player"))
	return type(level) == "number" and level or nil
end

-- instanceType: "party" = dungeon, "raid", "pvp", "arena", "scenario",
-- "none". Instance names are localized, but instanceID is stable, so the ID
-- is the comparison key (name only as a fallback).
function PlayerEvents:GetCurrentInstance()
	local inInstance, instanceType = IsInInstance()
	if ns.IsSecret(inInstance) or ns.IsSecret(instanceType) then
		return nil
	end
	if not inInstance or not instanceType or instanceType == "none" then
		return nil
	end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	return { name = notSecret(name), type = instanceType, id = notSecret(instanceID) or notSecret(name) }
end

function PlayerEvents:GetInstance()
	return self.instance
end

----------------------------------------------------------------------
-- Death
----------------------------------------------------------------------

-- PLAYER_DEAD isn't documented to fire exactly once per death (e.g. a
-- /reload while dead), and counting twice would spoil the stats. So we only
-- count again after PLAYER_ALIVE/PLAYER_UNGHOST. Confirmed in-game: one
-- message per death (TESTING.md #11).
function PlayerEvents:PLAYER_DEAD()
	ns.Log:Debug("PLAYER_DEAD (already counted: %s, UnitIsDeadOrGhost: %s)",
		tostring(self.dead), tostring(self:IsPlayerDeadOrGhost()))
	if self.dead then
		return
	end
	self.dead = true
	local instance = self.instance
	ns.Events:Fire("LP_PLAYER_DEAD", {
		drowned = self:WasDrowning(),
		zone = self:GetZone(),
		level = self:GetLevel(),
		inInstance = instance ~= nil,
		instanceName = instance and instance.name,
		instanceType = instance and instance.type,
		duringEncounter = ns.Events:IsEncounterActive(),
	})
end

-- PLAYER_ALIVE fires on resurrection and also when releasing to a ghost.
function PlayerEvents:PLAYER_ALIVE()
	local stillDead = self:IsPlayerDeadOrGhost()
	ns.Log:Debug("PLAYER_ALIVE (still dead or ghost: %s)", tostring(stillDead))
	if not stillDead then
		self.dead = false
	end
end

function PlayerEvents:PLAYER_UNGHOST()
	ns.Log:Debug("PLAYER_UNGHOST")
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

local function isPausedFlag(paused)
	return paused == true or (type(paused) == "number" and paused > 0)
end

-- Payload: value/maxValue in milliseconds; scale = change per second (-1 =
-- draining in real time, positive = refilling after surfacing); paused is a
-- number (0/1) per the docs, boolean on some clients.
function PlayerEvents:MIRROR_TIMER_START(_, timerName, value, _, scale, paused)
	if ns.IsSecret(timerName) or timerName ~= "BREATH" then
		return
	end
	if ns.IsSecret(value) or ns.IsSecret(scale) or ns.IsSecret(paused)
		or type(value) ~= "number" or type(scale) ~= "number" then
		self.breath = nil
		ns.Log:Debug("Breath timer values unavailable, drowning detection off")
		return
	end
	self.breath = { value = value, scale = scale, paused = isPausedFlag(paused), startedAt = GetTime() }
	self.breathStop = nil
end

function PlayerEvents:MIRROR_TIMER_PAUSE(_, timerName, paused)
	if ns.IsSecret(timerName) or timerName ~= "BREATH" or not self.breath or ns.IsSecret(paused) then
		return
	end
	-- Freeze or restart the countdown from the current remaining value.
	self.breath.value = self:BreathRemaining() or self.breath.value
	self.breath.startedAt = GetTime()
	self.breath.paused = isPausedFlag(paused)
end

function PlayerEvents:MIRROR_TIMER_STOP(_, timerName)
	if ns.IsSecret(timerName) or timerName ~= "BREATH" then
		return
	end
	if self.breath then
		self.breathStop = { at = GetTime(), remaining = self:BreathRemaining(), scale = self.breath.scale }
	end
	self.breath = nil
end

-- Milliseconds of breath left, or nil if unknown.
function PlayerEvents:BreathRemaining()
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

function PlayerEvents:WasDrowning()
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
-- Level up
----------------------------------------------------------------------

function PlayerEvents:PLAYER_LEVEL_UP(_, level)
	level = notSecret(level)
	if type(level) ~= "number" then
		level = nil
	end
	ns.Events:Fire("LP_PLAYER_LEVEL_UP", { level = level })
end

----------------------------------------------------------------------
-- Instance enter / leave
----------------------------------------------------------------------

-- PLAYER_ENTERING_WORLD fires after every loading screen, and entering or
-- leaving an instance always has one, so there's no polling. The flags tell
-- us when the loading screen came from a login or /reload rather than a move.
function PlayerEvents:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
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

function PlayerEvents:OnLeftInstance(instance)
	self.lastLeft = { id = instance.id, at = GetTime() }
	if self:IsPlayerDeadOrGhost() then
		return -- released after a wipe; the corpse run stays quiet
	end
	ns.Events:Fire("LP_INSTANCE_LEAVE", { name = instance.name, type = instance.type, id = instance.id })
end

function PlayerEvents:OnEnteredInstance(instance)
	local last = self.lastLeft
	if last and last.id == instance.id and GetTime() - last.at < self.REENTER_GRACE then
		return
	end
	ns.Events:Fire("LP_INSTANCE_ENTER", { name = instance.name, type = instance.type, id = instance.id })
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function PlayerEvents:OnEnable()
	ns.Events:Register(self, "PLAYER_LEVEL_UP")
	ns.Events:Register(self, "PLAYER_DEAD")
	ns.Events:Register(self, "PLAYER_ALIVE")
	ns.Events:Register(self, "PLAYER_UNGHOST")
	ns.Events:Register(self, "MIRROR_TIMER_START")
	ns.Events:Register(self, "MIRROR_TIMER_PAUSE")
	ns.Events:Register(self, "MIRROR_TIMER_STOP")
	ns.Events:Register(self, "PLAYER_ENTERING_WORLD")
	self.dead = self:IsPlayerDeadOrGhost()
	self.instance = self:GetCurrentInstance()
	self.instanceKnown = true
end
