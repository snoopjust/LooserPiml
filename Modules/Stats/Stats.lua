-- Stats: records what happens to the own character, keeps aggregates per
-- period and shares them (never the raw log) with friends.
--
-- Files:
--   Stats.lua       this module: storage, recording, compaction, played time,
--                   group time
--   Model.lua       pure data model (periods, aggregates, rollup) - no game API
--   Collectors.lua  game events -> Record() for most event types
--   Money.lua       gold changes with a source derived from context
--   Loot.lua        rare loot, crafting, gathering, skill-ups (loot/skill messages)
--   PvP.lua         duels, battlegrounds, honor
--   Sync.lua        sharing aggregates with friends, their stats cache
--
-- Storage (SavedVariables, per character because each client records only
-- its own character):
--   db.chars["Name-Realm"] = { log = { event, ... }, buckets = { [day] = aggregate },
--                              levelTime = { level, seconds, complete }, zones = { [name] = true } }
local _, ns = ...

local Stats = ns:NewModule("Stats")

Stats.TICK_INTERVAL = 60    -- seconds: played-time and group-time bookkeeping
Stats.MAX_TICK_GAP = 300    -- seconds: longer gaps (client frozen?) are not counted

Stats.defaults = {
	collect = true, -- setting: record stats at all
	share = true,   -- setting: send my aggregates to my LooserPiml friends
	chars = {},
	friendStats = {}, -- fullName -> latest aggregates received from that friend (Sync.lua)
}

function Stats:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, self.defaults)
	-- Read before anything is recorded this session: the evening recap is
	-- about the last day we were active before today (Tonight.lua).
	self.previousActiveDay = self.db.lastActiveDay
	self:RegisterOptions()
	self:RegisterUI() -- LeaderboardTab.lua
	self:RegisterProfilesTab() -- Profiles.lua
	if self.RegisterTonightTab then
		self:RegisterTonightTab() -- Tonight.lua
	end
end

function Stats:RegisterOptions()
	local L, Options = ns.L, ns.Options
	Options:AddSection("stats", L.OPT_SECTION_STATS, 30)
	Options:Add("stats", {
		type = "checkbox", key = "stats.collect", label = L.OPT_STATS_COLLECT, tooltip = L.OPT_STATS_COLLECT_TIP, default = true,
		get = function()
			return self.db.collect ~= false
		end,
		set = function(value)
			self.db.collect = value and true or false
		end,
	})
	Options:Add("stats", {
		type = "checkbox", key = "stats.share", label = L.OPT_STATS_SHARE, tooltip = L.OPT_STATS_SHARE_TIP, default = true,
		get = function()
			return self.db.share ~= false
		end,
		set = function(value)
			self.db.share = value and true or false
		end,
	})
	Options:Add("stats", {
		type = "button", label = L.OPT_STATS_RESET, buttonText = L.OPT_RESET_BUTTON, tooltip = L.OPT_STATS_RESET_TIP,
		onClick = function()
			Options:Confirm("RESET_STATS", L.OPT_STATS_RESET_CONFIRM, function()
				self:ResetMine()
				ns.Log:Print(L.STATS_RESET_DONE)
			end)
		end,
	})
	Options:Add("testing", {
		type = "button", label = L.OPT_TEST_SAMPLE_FRIENDS, buttonText = L.OPT_RUN_BUTTON, tooltip = L.OPT_TEST_SAMPLE_FRIENDS_TIP,
		onClick = function()
			if self:FillSampleFriends() then
				ns.Log:Print(L.SAMPLE_FRIENDS_DONE)
			else
				ns.Log:Print(L.SIM_NEEDS_TEST)
			end
		end,
	})
end

function Stats:OnEnable()
	local char = self:GetChar()
	self.Model.Compact(char.log, char.buckets, GetServerTime())
	self:StartLevelTimer()
	self.lastTick = GetTime()
	self.sessionStart = GetServerTime()
	C_Timer.After(self.Tonight.RECAP_DELAY, function()
		self:CheckEveningRecap()
	end)
	self.ticker = C_Timer.NewTicker(self.TICK_INTERVAL, function()
		self:Tick()
	end)
	ns.Events:Register(self, "PLAYER_LOGOUT", function()
		self:Tick() -- SavedVariables are written right after this
	end)
	self:EnableCollectors()
	-- "Share my gold" (Inventory settings): friends learn it with the next
	-- stats message, with or without gold.
	ns.Events:Register(self, "LP_SHARING_CHANGED", function(_, _, kind)
		if kind == "gold" then
			self:Changed()
		end
	end)
end

function Stats:OnDisable()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
end

----------------------------------------------------------------------
-- Storage
----------------------------------------------------------------------

function Stats:GetChar()
	local name = ns.Roster:GetPlayerName() or "?"
	local char = self.db.chars[name]
	if not char then
		char = { log = {}, buckets = {}, zones = {} }
		self.db.chars[name] = char
	end
	char.zones = char.zones or {}
	return char
end

function Stats:IsCollecting()
	return self:IsEnabled() and self.db.collect ~= false
end

-- Appends an event to the own log with the context every event carries.
-- Returns the event (nil when collecting is off).
function Stats:Record(eventType, data)
	if not self:IsCollecting() then
		return nil
	end
	local PlayerEvents = ns.PlayerEvents
	local instance = PlayerEvents:GetInstance()
	local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
	if ns.IsSecret(groupSize) then
		groupSize = nil
	end
	local event = {
		t = GetServerTime(),
		type = eventType,
		zone = PlayerEvents:GetZone(),
		level = PlayerEvents:GetLevel(),
		inInstance = instance ~= nil,
		instanceName = instance and instance.name,
		groupSize = groupSize,
		data = data or {},
	}
	local log = self:GetChar().log
	log[#log + 1] = event
	ns.Log:Debug("Stats: %s recorded", eventType)
	self:Changed()
	return event
end

-- Live counter in today's bucket (jumps, food, group time ...): too
-- frequent to log one by one. quiet: no LP_STATS_CHANGED (the value rides
-- along with the next stats message; used for the per-minute played and
-- group time, which would otherwise trigger a message every minute).
function Stats:Count(key, amount, quiet)
	if not self:IsCollecting() or not amount or amount == 0 then
		return
	end
	local now = GetServerTime()
	self.Model.Add(self.Model.Bucket(self:GetChar().buckets, now), key, amount, now)
	self:Changed(quiet)
end

function Stats:CountMap(mapName, key, amount, quiet)
	if not self:IsCollecting() or not key or not amount or amount == 0 then
		return
	end
	local bucket = self.Model.Bucket(self:GetChar().buckets, GetServerTime())
	bucket[mapName][key] = (bucket[mapName][key] or 0) + amount
	self:Changed(quiet)
end

function Stats:Changed(quiet)
	self.cache = nil
	self.db.lastActiveDay = self.Model.DayKey(GetServerTime())
	if not quiet then
		ns.Events:Fire("LP_STATS_CHANGED")
	end
end

-- Own aggregates { tonight, week, all }, cached until something changes or
-- the gaming day rolls over.
function Stats:GetAggregates()
	local now = GetServerTime()
	local day = self.Model.DayKey(now)
	if not self.cache or self.cacheDay ~= day then
		local char = self:GetChar()
		self.cache = self.Model.AggregateAll(char.log, char.buckets, now)
		self.cacheDay = day
	end
	return self.cache
end

-- Gold on hand right now (copper), or nil if "Share my gold" is off or the
-- value isn't readable. Used for my own leaderboard entry and the STATS
-- message; someone who doesn't share takes no part in the gold comparison,
-- not even on their own screen.
function Stats:GetSharedGold()
	if not ns.DB:IsShared("gold") or not GetMoney then
		return nil
	end
	local money = GetMoney()
	if ns.IsSecret(money) or type(money) ~= "number" or money < 0 then
		return nil
	end
	return math.floor(money)
end

-- Wipes the own character's stats (settings button, with confirmation).
function Stats:ResetMine()
	local name = ns.Roster:GetPlayerName() or "?"
	self.db.chars[name] = nil
	self:StartLevelTimer()
	self:Changed()
end

----------------------------------------------------------------------
-- Played time per level
----------------------------------------------------------------------
-- RequestTimePlayed would give exact /played numbers, but it prints them
-- into the chat frame, so we measure our own session time instead. A level
-- counts as "complete" only if we saw it start (level-up while recording);
-- the level we were at when the addon was installed is partial.

function Stats:StartLevelTimer()
	local char = self:GetChar()
	local level = ns.PlayerEvents:GetLevel()
	local timer = char.levelTime
	if not timer or timer.level ~= level then
		char.levelTime = { level = level, seconds = 0, complete = false }
	end
	self.levelTickAt = GetTime()
end

function Stats:AccumulatePlayed()
	local now = GetTime()
	local timer = self:GetChar().levelTime
	if timer and self.levelTickAt then
		local elapsed = now - self.levelTickAt
		if elapsed > 0 and elapsed <= self.MAX_TICK_GAP then
			timer.seconds = timer.seconds + elapsed
		end
	end
	self.levelTickAt = now
end

function Stats:OnPlayerLevelUp(_, info)
	self:AccumulatePlayed()
	local char = self:GetChar()
	local timer = char.levelTime
	local complete = timer and timer.complete and info.level and timer.level == info.level - 1
	self:Record("level_up", {
		level = info.level,
		played = timer and math.floor(timer.seconds) or nil,
		complete = complete or nil,
	})
	char.levelTime = { level = info.level, seconds = 0, complete = true }
end

----------------------------------------------------------------------
-- Periodic bookkeeping
----------------------------------------------------------------------

-- Seconds since the last tick, or 0 if the gap is implausible.
function Stats:TakeElapsed()
	local now = GetTime()
	local elapsed = now - (self.lastTick or now)
	self.lastTick = now
	if elapsed <= 0 or elapsed > self.MAX_TICK_GAP then
		return 0
	end
	return elapsed
end

-- Played time (playedSeconds, for the profile) and time spent grouped:
-- total and per LooserPiml friend in the group (handshake answered this
-- session). Grouping is only recorded as context here; nothing in
-- LooserPiml requires it.
function Stats:Tick()
	self:AccumulatePlayed()
	local elapsed = math.floor(self:TakeElapsed() + 0.5)
	if elapsed == 0 then
		return
	end
	self:Count("playedSeconds", elapsed, true)
	if not ns.Roster:IsInGroup() then
		return
	end
	self:Count("groupSeconds", elapsed, true)
	for _, member in ipairs(ns.Roster:GetOthers()) do
		if not member.fake and ns.Friends:IsConfirmed(member.name) then
			self:CountMap("groupWith", member.name, elapsed, true)
		end
	end
end
