-- Ticker: announces what happens to your LooserPiml friends, wherever
-- they are: grouped or not doesn't matter. Detection of the own player's
-- events lives in Core/PlayerEvents.lua; the Ticker shows them locally and
-- sends them to every connected friend (never to anyone else, see
-- Core/Friends.lua); receivers count and display them as a banner, a chat
-- line only, or not at all (setting "Ticker messages from friends").
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
Ticker.FRIEND_MODES = { banner = true, chat = true, off = true }

Ticker.defaults = {
	stats = {},     -- session/all-time counters from TICK messages, see Stats.lua
	chatLog = true, -- also print each event as a local chat line
	-- Which messages are shown (display only: stats and broadcasting don't care)
	show = { levelup = true, death = true, drowned = true, dungeon = true, raid = true, bossRecap = true, own = true },
	-- How friends' events are shown: "banner" (banner + chat line), "chat" (chat line only), "off"
	friendsDisplay = "banner",
	-- Banner look; point = { point, relativePoint, x, y } once moved
	banner = { hold = 4, size = 40, sound = true },
}

-- Display filter key of an event (see the "show" settings).
function Ticker:FilterKey(data)
	if data.k == "death" then
		return data.dr and "drowned" or "death"
	elseif data.k == "levelup" then
		return "levelup"
	elseif data.k == "enter" or data.k == "leave" then
		return data.it == "raid" and "raid" or "dungeon"
	end
	return nil
end

function Ticker:ShouldShow(data, isOwn)
	local show = self.db.show
	if isOwn and show.own == false then
		return false
	end
	local key = self:FilterKey(data)
	return not key or show[key] ~= false
end

function Ticker:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, self.defaults)
	ns.Slash:Register("sound", function(arg)
		arg = arg:lower()
		if arg == "on" or arg == "off" then
			self.db.banner.sound = arg == "on"
		end
		ns.Log:Print(L.SOUND_STATE, self.db.banner.sound and L.ON or L.OFF)
	end, "on/off", L.HELP_SOUND)
	self:RegisterOptions()
end

function Ticker:GetFriendsDisplay()
	local mode = self.db.friendsDisplay
	return self.FRIEND_MODES[mode] and mode or "banner"
end

function Ticker:RegisterOptions()
	local Options = ns.Options
	Options:AddSection("ticker", L.OPT_SECTION_TICKER, 10)
	Options:Add("ticker", {
		type = "dropdown", key = "ticker.friends", label = L.OPT_TICKER_FRIENDS, tooltip = L.OPT_TICKER_FRIENDS_TIP,
		default = "banner",
		values = {
			{ value = "banner", label = L.OPT_TICKER_FRIENDS_BANNER },
			{ value = "chat", label = L.OPT_TICKER_FRIENDS_CHAT },
			{ value = "off", label = L.OPT_TICKER_FRIENDS_OFF },
		},
		get = function()
			return self:GetFriendsDisplay()
		end,
		set = function(value)
			self.db.friendsDisplay = value
		end,
	})
	for _, entry in ipairs({
		{ "levelup", L.OPT_SHOW_LEVELUP },
		{ "death", L.OPT_SHOW_DEATH },
		{ "drowned", L.OPT_SHOW_DROWNED },
		{ "dungeon", L.OPT_SHOW_DUNGEON },
		{ "raid", L.OPT_SHOW_RAID },
		{ "bossRecap", L.OPT_SHOW_BOSS_RECAP, L.OPT_SHOW_BOSS_RECAP_TIP },
		{ "own", L.OPT_SHOW_OWN },
	}) do
		local key = entry[1]
		Options:Add("ticker", {
			type = "checkbox", key = "ticker." .. key, label = entry[2], tooltip = entry[3], default = true,
			get = function()
				return self.db.show[key] ~= false
			end,
			set = function(value)
				self.db.show[key] = value and true or false
			end,
		})
	end

	Options:AddSection("banner", L.OPT_SECTION_BANNER, 20)
	Options:Add("banner", {
		type = "slider", key = "banner.hold", label = L.OPT_BANNER_HOLD, default = 4, min = 2, max = 10, step = 0.5,
		format = function(value)
			return string.format("%.1f s", value)
		end,
		get = function()
			return self.db.banner.hold
		end,
		set = function(value)
			self.db.banner.hold = value
			self.Display:ApplyStyle()
		end,
	})
	Options:Add("banner", {
		type = "slider", key = "banner.size", label = L.OPT_BANNER_SIZE, default = 40, min = 20, max = 64, step = 2,
		format = function(value)
			return tostring(math.floor(value))
		end,
		get = function()
			return self.db.banner.size
		end,
		set = function(value)
			self.db.banner.size = value
			self.Display:ApplyStyle()
		end,
	})
	Options:Add("banner", {
		type = "checkbox", key = "banner.sound", label = L.OPT_BANNER_SOUND, default = true,
		get = function()
			return self.db.banner.sound ~= false
		end,
		set = function(value)
			self.db.banner.sound = value and true or false
		end,
	})
	Options:Add("banner", {
		type = "button", label = L.OPT_BANNER_MOVE, buttonText = L.OPT_BANNER_MOVE_BUTTON, tooltip = L.OPT_BANNER_MOVE_TIP,
		onClick = function()
			self.Display:ToggleUnlocked()
		end,
	})
	Options:Add("banner", {
		type = "button", label = L.OPT_BANNER_RESET, buttonText = L.OPT_RESET_BUTTON,
		onClick = function()
			self.Display:ResetPosition()
		end,
	})
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
	-- "/lp stats chat" (Window owns "/lp stats" and asks for the text ranking)
	ns.Events:Register(self, "LP_PRINT_STATS", function()
		self.Stats:PrintReport()
	end)
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
	if self:ShouldShow(data, true) then
		self.Display:ShowEvent(me, data, { test = isTest })
	end
	-- "friends": every connected LooserPiml friend, grouped or not.
	return ns.Comm:Send(self.MSG, data, { scope = "friends" })
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
	-- Always counted; how (or whether) it is shown is the receiver's choice.
	self.Stats:Record(sender, event, meta.test)
	local mode = self:GetFriendsDisplay()
	if mode ~= "off" and self:ShouldShow(event, false) then
		self.Display:ShowEvent(sender, event, { late = meta.late, test = meta.test, chatOnly = mode == "chat" })
	end
end

----------------------------------------------------------------------
-- Test mode
----------------------------------------------------------------------

-- name == nil simulates the player (local display + loopback broadcast);
-- otherwise a message "from" that (fake) friend is received.
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
