-- Ticker counters: deaths, drownings and level-ups per player.
--
-- Session counters live in memory (they include test-mode events).
-- All-time counters live in SavedVariables and only count real events:
--   LooserPimlDB.modules.Ticker.stats["Name-Realm"] = { deaths, drowned, levelUps, level, class }
local _, ns = ...
local L = ns.L

local Ticker = ns:GetModule("Ticker")

local Stats = {}
Ticker.Stats = Stats

Stats.session = {}

local function counters(store, name)
	local entry = store[name]
	if not entry then
		entry = { deaths = 0, drowned = 0, levelUps = 0 }
		store[name] = entry
	end
	return entry
end

function Stats:Record(name, data, isTest)
	if not name then
		return
	end
	local stores = { self.session }
	if not isTest then
		stores[2] = Ticker.db.stats
	end
	for _, store in ipairs(stores) do
		local entry = counters(store, name)
		if data.k == "death" then
			entry.deaths = entry.deaths + 1
			if data.dr then
				entry.drowned = entry.drowned + 1
			end
		elseif data.k == "levelup" then
			entry.levelUps = entry.levelUps + 1
			if data.lvl then
				entry.level = data.lvl
			end
		end
		if data.c then
			entry.class = data.c
		end
	end
end

-- scope: "session" | "alltime"
function Stats:Get(name, scope)
	local store = scope == "alltime" and Ticker.db.stats or self.session
	return store[name]
end

function Stats:GetSessionDeaths(name)
	local entry = self.session[name]
	return entry and entry.deaths or 0
end

-- Sorted list of { name, value, class } with value > 0, highest first.
function Stats:Ranking(field, scope)
	local store = scope == "alltime" and Ticker.db.stats or self.session
	local list = {}
	for name, entry in pairs(store) do
		local value = entry[field] or 0
		if value > 0 then
			list[#list + 1] = { name = name, value = value, class = entry.class }
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.name < b.name
	end)
	return list
end

local function formatRanking(list)
	if #list == 0 then
		return L.STATS_NONE
	end
	local parts = {}
	for i = 1, math.min(#list, 10) do
		local row = list[i]
		parts[#parts + 1] = string.format("%s (%d)", ns.Roster:ColorName(row.name, row.class), row.value)
	end
	return table.concat(parts, ", ")
end

-- Report lines (also used by tests).
function Stats:BuildReport()
	local lines = {}
	local deaths = self:Ranking("deaths", "session")
	if deaths[1] then
		lines[#lines + 1] = L.STATS_DEATH_KING:format(ns.Roster:ColorName(deaths[1].name, deaths[1].class), deaths[1].value)
	else
		lines[#lines + 1] = L.STATS_NO_DEATHS
	end
	local sections = {
		{ L.STATS_DEATHS_SESSION, "deaths", "session" },
		{ L.STATS_DEATHS_ALLTIME, "deaths", "alltime" },
		{ L.STATS_DROWNED_ALLTIME, "drowned", "alltime" },
		{ L.STATS_LEVELUPS_SESSION, "levelUps", "session" },
		{ L.STATS_LEVELUPS_ALLTIME, "levelUps", "alltime" },
	}
	for _, section in ipairs(sections) do
		lines[#lines + 1] = L.STATS_LINE:format(section[1], formatRanking(self:Ranking(section[2], section[3])))
	end
	return lines
end

function Stats:PrintReport()
	ns.Log:Print(L.STATS_HEADER)
	for _, line in ipairs(self:BuildReport()) do
		ns.Log:Print(line)
	end
end
