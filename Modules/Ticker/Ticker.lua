-- Ticker: announces what happens to group members. Detection of the own
-- player's events lives in Core/PlayerEvents.lua; the Ticker shows them
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
Ticker.ANNOUNCED_INSTANCES = { party = true, raid = true } -- not battlegrounds/arenas/scenarios
Ticker.MAX_TEXT = 64 -- max length of names coming from other clients

Ticker.defaults = {
	stats = {},     -- all-time counters from TICK messages, see Stats.lua
	chatLog = true, -- also print each event as a local chat line
	sound = true,   -- play a sound when a banner appears
}

function Ticker:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, self.defaults)
	ns.Slash:Register("stats", function()
		if self:IsEnabled() then
			self.Stats:PrintReport()
		end
	end, "", L.HELP_STATS)
	ns.Slash:Register("sound", function(arg)
		arg = arg:lower()
		if arg == "on" or arg == "off" then
			self.db.sound = arg == "on"
		end
		ns.Log:Print(L.SOUND_STATE, self.db.sound and L.ON or L.OFF)
	end, "on/off", L.HELP_SOUND)
end

function Ticker:OnEnable()
	ns.Events:Register(self, "LP_PLAYER_DEAD", "OnPlayerDead")
	ns.Events:Register(self, "LP_PLAYER_LEVEL_UP", "OnPlayerLevelUp")
	ns.Events:Register(self, "LP_INSTANCE_ENTER", "OnInstanceEnter")
	ns.Events:Register(self, "LP_INSTANCE_LEAVE", "OnInstanceLeave")
	ns.Events:Register(self, "LP_ENCOUNTER_START", function()
		self.Display:OnEncounterStart()
	end)
	ns.Events:Register(self, "LP_ENCOUNTER_END", function()
		self.Display:OnEncounterEnd()
	end)
	ns.Comm:RegisterHandler(self, self.MSG, self.OnTick)
	ns.TestMode:RegisterSim(self, { "death", "drown", "levelup", "enter", "leave" }, self.Simulate)
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

function Ticker:OnPlayerDead(_, info)
	self:OnOwnEvent("death", { dr = info.drowned or nil, z = info.zone })
end

function Ticker:OnPlayerLevelUp(_, info)
	self:OnOwnEvent("levelup", { lvl = info.level })
end

function Ticker:OnInstanceEnter(_, info)
	if self.ANNOUNCED_INSTANCES[info.type] then
		self:OnOwnEvent("enter", { i = info.name, it = info.type })
	end
end

function Ticker:OnInstanceLeave(_, info)
	if self.ANNOUNCED_INSTANCES[info.type] then
		self:OnOwnEvent("leave", { i = info.name, it = info.type })
	end
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
-- Simulations bypass Core/PlayerEvents on purpose, so Stats never sees them.
function Ticker:Simulate(kind, name)
	local data
	if kind == "death" then
		data = { k = "death", z = ns.PlayerEvents:GetZone() }
	elseif kind == "drown" then
		data = { k = "death", dr = true }
	elseif kind == "levelup" then
		local level = ns.PlayerEvents:GetLevel()
		data = { k = "levelup", lvl = name and math.random(2, 60) or (level and level + 1 or nil) }
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
