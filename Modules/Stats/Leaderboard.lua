-- Leaderboard data provider: awards and rankings from a list of
-- participants ({ name, class, agg, isSelf, ... }, see Sync.lua
-- GetParticipants). Pure Lua - the frame code in LeaderboardTab.lua only
-- renders what this returns.
local _, ns = ...

local Stats = ns:GetModule("Stats")

local Leaderboard = {}
Stats.Leaderboard = Leaderboard

-- Hall of Fame cards. better: "high" = biggest value wins, "low" = smallest.
-- tieKey: aggregate timestamp used for "the earlier achiever wins".
-- snapshot: the value is the participant's current state (gold on hand),
-- not a per-period aggregate, so the period selector doesn't apply, and
-- participants without the value (they don't share it) are left out.
Leaderboard.AWARDS = {
	{ id = "deathKing", metric = "deaths", better = "high", tieKey = "deaths", format = "number" },
	{ id = "fishFood", metric = "drowned", better = "high", tieKey = "drowned", format = "number" },
	{ id = "goldHoarder", metric = "gold", better = "high", format = "money", snapshot = true },
	{ id = "speedrunner", metric = "avgLevelTime", better = "low", tieKey = "levelTime", format = "duration" },
}

-- Ranking list metrics (selector order).
Leaderboard.METRICS = {
	{ id = "deaths", metric = "deaths", tieKey = "deaths", format = "number" },
	{ id = "gold", metric = "gold", format = "money", snapshot = true },
	{ id = "quests", metric = "quests", tieKey = "quests", format = "number" },
	{ id = "levelups", metric = "levelUps", tieKey = "levelUps", format = "number" },
}

local function find(list, id)
	for _, entry in ipairs(list) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- Value of a metric for a participant; nil if there is nothing to show.
-- "gold" is the snapshot participant.gold (nil: not shared), everything
-- else comes from the period aggregate.
function Leaderboard.Value(participant, metric)
	if metric == "gold" then
		return participant.gold
	end
	local agg = participant.agg
	if not agg then
		return nil
	end
	if metric == "avgLevelTime" then
		return Stats.Model.AverageLevelTime(agg)
	end
	return agg.n and agg.n[metric] or nil
end

local function achievedAt(participant, tieKey)
	local at = tieKey and participant.agg and participant.agg.at and participant.agg.at[tieKey]
	return at or math.huge -- unknown: counts as "later"
end

-- Sorts entries ({ participant, value }) best first: by value, then who got
-- there earlier, then by name so the order is always the same.
local function sortEntries(entries, better, tieKey)
	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			if better == "low" then
				return a.value < b.value
			end
			return a.value > b.value
		end
		local atA, atB = achievedAt(a.participant, tieKey), achievedAt(b.participant, tieKey)
		if atA ~= atB then
			return atA < atB
		end
		return a.participant.name < b.participant.name
	end)
end

-- Winner of one award or nil ("No one yet"). Zero never wins a "high"
-- award: nobody is Death King with 0 deaths.
function Leaderboard.Award(participants, awardOrId)
	local award = type(awardOrId) == "table" and awardOrId or find(Leaderboard.AWARDS, awardOrId)
	local entries = {}
	for _, participant in ipairs(participants or {}) do
		local value = Leaderboard.Value(participant, award.metric)
		if value and (award.better == "low" or value > 0) then
			entries[#entries + 1] = { participant = participant, value = value }
		end
	end
	if #entries == 0 then
		return nil
	end
	sortEntries(entries, award.better, award.tieKey)
	local best = entries[1]
	return { name = best.participant.name, class = best.participant.class, value = best.value, isSelf = best.participant.isSelf }
end

function Leaderboard.HallOfFame(participants)
	local cards = {}
	for _, award in ipairs(Leaderboard.AWARDS) do
		cards[#cards + 1] = { award = award, winner = Leaderboard.Award(participants, award) }
	end
	return cards
end

-- Rows for the ranking list: everyone, best first, with the bar length
-- relative to the leader (0..1). Snapshot metrics (gold) list only
-- participants who share that value.
function Leaderboard.Ranking(participants, metricId)
	local metric = find(Leaderboard.METRICS, metricId) or Leaderboard.METRICS[1]
	local entries = {}
	for _, participant in ipairs(participants or {}) do
		local value = Leaderboard.Value(participant, metric.metric)
		if value or not metric.snapshot then
			entries[#entries + 1] = { participant = participant, value = value or 0 }
		end
	end
	sortEntries(entries, "high", metric.tieKey)
	local leader = entries[1] and entries[1].value or 0
	local rows = {}
	for i, entry in ipairs(entries) do
		local p = entry.participant
		rows[i] = {
			rank = i,
			name = p.name,
			class = p.class,
			value = entry.value,
			fraction = leader > 0 and entry.value / leader or 0,
			isSelf = p.isSelf,
			online = p.online,
			lastSeen = p.lastSeen,
		}
	end
	return rows, metric
end

-- "12g 3s", "1h 05m", "7" for a metric format.
function Leaderboard.Format(value, format)
	if value == nil then
		return "-"
	elseif format == "money" then
		return ns.Util.FormatMoney(value)
	elseif format == "duration" then
		return ns.Util.FormatDuration(value)
	end
	return tostring(math.floor(value + 0.5))
end
