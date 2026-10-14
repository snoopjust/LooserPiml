-- Pure stats data model. No frames, no game API calls except the Lua time
-- functions `date` and `time`, which WoW provides. Everything here is
-- exercised offline by spec/stats_model_spec.lua.
--
-- Shapes
--   event     { t = server time, type = "death", zone, level, inInstance,
--               instanceName, groupSize, data = { ... } }       (raw log entry)
--   aggregate { n = { deaths = 3, ... },          counters
--               moneyIn = { loot = copper, ... }, moneyOut = { repair = ..., ... },
--               groupWith = { ["Max-Realm"] = seconds },
--               at = { deaths = t, ... },          when a counter last changed (tie-breaks)
--               last = { honor = { v, t }, ... },  snapshots (latest wins)
--               maxLevel = n }
--   buckets   { ["2026-10-11"] = aggregate }     one aggregate per gaming day
--
-- A "gaming day" starts at DAY_START_HOUR local time, so a session that runs
-- past midnight still counts as "tonight".
local _, ns = ...

local Stats = ns:GetModule("Stats")

local Model = {}
Stats.Model = Model

Model.VERSION = 1          -- aggregate format; bump on incompatible changes (sent with sync)
Model.DAY_START_HOUR = 6
Model.MAX_EVENTS = 5000    -- raw log cap ...
Model.MAX_AGE_DAYS = 30    -- ... or this age, whichever comes first
Model.PERIODS = { "tonight", "week", "all" }

----------------------------------------------------------------------
-- Time
----------------------------------------------------------------------

local SHIFT = Model.DAY_START_HOUR * 3600

-- Timestamp of the start of the gaming day containing t.
function Model.DayStart(t)
	local d = date("*t", t - SHIFT)
	return time({ year = d.year, month = d.month, day = d.day, hour = Model.DAY_START_HOUR, min = 0, sec = 0 })
end

-- "YYYY-MM-DD" of the gaming day containing t (sorts as text).
function Model.DayKey(t)
	return date("%Y-%m-%d", t - SHIFT)
end

-- Timestamp of Monday DAY_START_HOUR of the gaming week containing t.
-- Built from date tables (not "minus 7 * 86400") so DST changes don't
-- shift it by an hour.
function Model.WeekStart(t)
	local d = date("*t", Model.DayStart(t))
	local sinceMonday = (d.wday + 5) % 7 -- wday: 1 = Sunday
	return time({ year = d.year, month = d.month, day = d.day - sinceMonday, hour = Model.DAY_START_HOUR, min = 0, sec = 0 })
end

function Model.WeekKey(t)
	return Model.DayKey(Model.WeekStart(t))
end

-- Start timestamp of a period, nil for "all".
function Model.PeriodStart(period, now)
	if period == "tonight" then
		return Model.DayStart(now)
	elseif period == "week" then
		return Model.WeekStart(now)
	end
	return nil
end

----------------------------------------------------------------------
-- Aggregates
----------------------------------------------------------------------

function Model.Empty()
	return { n = {}, moneyIn = {}, moneyOut = {}, groupWith = {}, at = {}, last = {} }
end

local function add(agg, key, amount, t)
	if not amount or amount == 0 then
		return
	end
	agg.n[key] = (agg.n[key] or 0) + amount
	if t and (not agg.at[key] or t > agg.at[key]) then
		agg.at[key] = t
	end
end
Model.Add = add

local function addMap(map, key, amount)
	if key and amount and amount ~= 0 then
		map[key] = (map[key] or 0) + amount
	end
end

local function snapshot(agg, key, value, t)
	if value == nil then
		return
	end
	local current = agg.last[key]
	if not current or t >= current.t then
		agg.last[key] = { v = value, t = t }
	end
end

-- How each event type changes an aggregate. Unknown types are ignored, so
-- old clients can read logs written by newer ones.
local handlers = {}

handlers.death = function(agg, e, d)
	add(agg, "deaths", 1, e.t)
	if d.drowned then
		add(agg, "drowned", 1, e.t)
	end
	if e.inInstance then
		add(agg, "deathsInInstance", 1, e.t)
	end
	if d.duringEncounter then
		add(agg, "deathsInEncounter", 1, e.t)
	end
end

handlers.level_up = function(agg, e, d)
	add(agg, "levelUps", 1, e.t)
	if type(d.level) == "number" and (not agg.maxLevel or d.level > agg.maxLevel) then
		agg.maxLevel = d.level
	end
	-- Only levels we watched from start to finish count for "time per level".
	if d.complete and type(d.played) == "number" and d.played > 0 then
		add(agg, "levelTime", d.played, e.t)
		add(agg, "levelTimeCount", 1, e.t)
	end
end

handlers.quest_done = function(agg, e, d)
	add(agg, "quests", 1, e.t)
	add(agg, "questXP", d.xp, e.t)
	add(agg, "questMoney", d.money, e.t)
end

handlers.money = function(agg, e, d)
	local delta, source = d.delta, d.source or "other"
	if type(delta) ~= "number" or delta == 0 then
		return
	end
	if delta > 0 then
		add(agg, "moneyIn", delta, e.t)
		addMap(agg.moneyIn, source, delta)
		if source == "loot" then
			add(agg, "moneyLooted", delta, e.t)
		end
	else
		add(agg, "moneyOut", -delta, e.t)
		addMap(agg.moneyOut, source, -delta)
	end
end

handlers.loot_rare = function(agg, e, d)
	local quality = d.quality or 0
	add(agg, "lootRare", 1, e.t)
	if quality == 4 then
		add(agg, "lootEpic", 1, e.t)
	elseif quality >= 5 then
		add(agg, "lootLegendary", 1, e.t)
	end
end

handlers.instance = function(agg, e, d)
	if d.action ~= "enter" then
		return
	end
	add(agg, "instancesEntered", 1, e.t)
	if d.itype == "party" then
		add(agg, "dungeons", 1, e.t)
	elseif d.itype == "raid" then
		add(agg, "raids", 1, e.t)
	end
end

handlers.encounter = function(agg, e, d)
	add(agg, d.success and "bossKills" or "bossWipes", 1, e.t)
end

handlers.profession = function(agg, e, d)
	if d.kind == "skillup" then
		add(agg, "skillUps", 1, e.t)
		if d.profession then
			add(agg, "professionSkillUps", 1, e.t)
		end
	elseif d.kind == "crafted" then
		add(agg, "crafted", d.count or 1, e.t)
	elseif d.kind == "gathered" then
		add(agg, "gathered", 1, e.t)
	end
end

handlers.travel = function(agg, e, d)
	if d.kind == "zone_new" then
		add(agg, "zonesDiscovered", 1, e.t)
	elseif d.kind == "flight" then
		add(agg, "flights", 1, e.t)
	elseif d.kind == "hearth" then
		add(agg, "hearths", 1, e.t)
	end
end

handlers.duel = function(agg, e, d)
	local r = d.result
	if r == "won" or r == "opponent_fled" then
		add(agg, "duelsWon", 1, e.t)
	elseif r == "lost" or r == "fled" then
		add(agg, "duelsLost", 1, e.t)
		if r == "fled" then
			add(agg, "duelsFled", 1, e.t)
		end
	end
end

handlers.pvp = function(agg, e, d)
	if d.kind == "joined" then
		add(agg, "bgJoined", 1, e.t)
	elseif d.kind == "finished" then
		add(agg, "bgFinished", 1, e.t)
		if d.won == true then
			add(agg, "bgWon", 1, e.t)
		elseif d.won == false then
			add(agg, "bgLost", 1, e.t)
		end
		add(agg, "bgKillingBlows", d.killingBlows, e.t)
		add(agg, "bgHonorableKills", d.honorableKills, e.t)
	elseif d.kind == "deserted" then
		add(agg, "bgDeserted", 1, e.t)
	elseif d.kind == "honor" then
		snapshot(agg, "honor", d.honor, e.t)
		snapshot(agg, "honorLevel", d.honorLevel, e.t)
	end
end

function Model.AddEvent(agg, e)
	local handler = handlers[e.type]
	if handler then
		handler(agg, e, e.data or {})
	end
	return agg
end

function Model.Merge(into, other)
	for key, value in pairs(other.n or {}) do
		into.n[key] = (into.n[key] or 0) + value
	end
	for _, mapName in ipairs({ "moneyIn", "moneyOut", "groupWith" }) do
		for key, value in pairs(other[mapName] or {}) do
			into[mapName][key] = (into[mapName][key] or 0) + value
		end
	end
	for key, t in pairs(other.at or {}) do
		if not into.at[key] or t > into.at[key] then
			into.at[key] = t
		end
	end
	for key, snap in pairs(other.last or {}) do
		snapshot(into, key, snap.v, snap.t)
	end
	if other.maxLevel and (not into.maxLevel or other.maxLevel > into.maxLevel) then
		into.maxLevel = other.maxLevel
	end
	return into
end

----------------------------------------------------------------------
-- Log + buckets
----------------------------------------------------------------------

-- Bucket for the gaming day of t (created on demand). Live counters that are
-- never logged one by one (jumps, food, group time) go straight in here.
function Model.Bucket(buckets, t)
	local key = Model.DayKey(t)
	local bucket = buckets[key]
	if not bucket then
		bucket = Model.Empty()
		buckets[key] = bucket
	end
	return bucket
end

-- Rolls events that are too old (or beyond the cap, oldest first) into
-- daily buckets and drops them from the log. Totals stay identical.
-- Returns the number of events rolled up.
function Model.Compact(log, buckets, now, maxEvents, maxAgeDays)
	maxEvents = maxEvents or Model.MAX_EVENTS
	maxAgeDays = maxAgeDays or Model.MAX_AGE_DAYS
	local cutoff = now - maxAgeDays * 86400
	local excess = #log - maxEvents
	local rolled = 0
	for i, e in ipairs(log) do
		if i <= excess or e.t < cutoff then
			Model.AddEvent(Model.Bucket(buckets, e.t), e)
			rolled = i
		else
			break -- the log is in time order
		end
	end
	if rolled > 0 then
		local keep = #log - rolled
		for i = 1, keep do
			log[i] = log[i + rolled]
		end
		for i = #log, keep + 1, -1 do
			log[i] = nil
		end
	end
	return rolled
end

-- Aggregate of everything from `startTime` on (nil = all time).
function Model.Aggregate(log, buckets, startTime)
	local agg = Model.Empty()
	local startDay = startTime and Model.DayKey(startTime)
	for day, bucket in pairs(buckets) do
		if not startDay or day >= startDay then
			Model.Merge(agg, bucket)
		end
	end
	for _, e in ipairs(log) do
		if not startTime or e.t >= startTime then
			Model.AddEvent(agg, e)
		end
	end
	return agg
end

-- { tonight = agg, week = agg, all = agg }
function Model.AggregateAll(log, buckets, now)
	local result = {}
	for _, period in ipairs(Model.PERIODS) do
		result[period] = Model.Aggregate(log, buckets, Model.PeriodStart(period, now))
	end
	return result
end

----------------------------------------------------------------------
-- Derived values
----------------------------------------------------------------------

function Model.Get(agg, key)
	return agg and agg.n[key] or 0
end

-- Average played seconds per fully observed level, or nil.
function Model.AverageLevelTime(agg)
	local count = Model.Get(agg, "levelTimeCount")
	if count == 0 then
		return nil
	end
	return Model.Get(agg, "levelTime") / count
end

----------------------------------------------------------------------
-- Aggregates sent to / received from other clients
----------------------------------------------------------------------

-- Counters whose "when" is needed by others (award tie-breaks). Sending
-- every timestamp would roughly double the message size for nothing.
Model.TIE_KEYS = { "deaths", "drowned", "levelTime", "levelUps", "quests" }

-- Copy of an aggregate for the network: timestamps only for TIE_KEYS.
function Model.ForSync(agg)
	local out = {
		n = agg.n,
		moneyIn = agg.moneyIn,
		moneyOut = agg.moneyOut,
		groupWith = agg.groupWith,
		last = agg.last,
		maxLevel = agg.maxLevel,
		at = {},
	}
	for _, key in ipairs(Model.TIE_KEYS) do
		out.at[key] = agg.at[key]
	end
	return out
end

local MAX_NUMBER = 1e13 -- far above any real copper or second count
local MAX_KEYS = 100

local function cleanNumber(v)
	if type(v) ~= "number" or v ~= v or v < 0 or v > MAX_NUMBER then
		return nil
	end
	return v
end

local function cleanKey(k)
	if type(k) ~= "string" or k == "" or #k > 64 then
		return nil
	end
	return (k:gsub("|", "")) -- never let escape sequences reach the UI
end

local function cleanMap(map)
	local out, count = {}, 0
	if type(map) ~= "table" then
		return out
	end
	for k, v in pairs(map) do
		local key, value = cleanKey(k), cleanNumber(v)
		if key and value then
			count = count + 1
			if count > MAX_KEYS then
				break
			end
			out[key] = value
		end
	end
	return out
end

-- Copies only well-formed fields. The data comes from another client
-- (possibly older, newer or buggy), so nothing is trusted.
function Model.Sanitize(agg)
	if type(agg) ~= "table" then
		return Model.Empty()
	end
	local clean = Model.Empty()
	clean.n = cleanMap(agg.n)
	clean.moneyIn = cleanMap(agg.moneyIn)
	clean.moneyOut = cleanMap(agg.moneyOut)
	clean.groupWith = cleanMap(agg.groupWith)
	clean.at = cleanMap(agg.at)
	if type(agg.last) == "table" then
		for k, snap in pairs(agg.last) do
			local key = cleanKey(k)
			if key and type(snap) == "table" and cleanNumber(snap.v) and cleanNumber(snap.t) then
				clean.last[key] = { v = snap.v, t = snap.t }
			end
		end
	end
	clean.maxLevel = cleanNumber(agg.maxLevel)
	return clean
end
