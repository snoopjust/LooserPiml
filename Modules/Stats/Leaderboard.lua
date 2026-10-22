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
	-- Confirmed ranked duel wins in the period (Ladder.Annotate: both sides
	-- agree, disputed duels left out), not the claims in the aggregate.
	{ id = "duelKing", metric = "rankedWins", better = "high", tieKey = "rankedWins", format = "number" },
}

-- Hall of Shame cards (same rules, from the bottom). latest = true: a tie
-- goes to whoever got there LAST (the fresh shame), unknown times count as
-- "earliest". Zero never "wins" a high shame either (no Kangaroo with 0
-- jumps); for the low ones (Broke, Noob) every value counts, 0 gold too.
-- looserPiml: last place of the all-time duel ladder (Leaderboard.LooserPiml),
-- independent of the period like the snapshots.
Leaderboard.SHAME = {
	{ id = "broke", metric = "gold", better = "low", format = "money", snapshot = true, latest = true },
	{ id = "noob", metric = "level", better = "low", format = "number", snapshot = true, latest = true },
	{ id = "looserPiml", special = "looserPiml", format = "record", snapshot = true },
	{ id = "slowpoke", metric = "avgLevelTime", better = "high", tieKey = "levelTime", format = "duration", latest = true },
	{ id = "bossSnack", metric = "deathsInEncounter", better = "high", tieKey = "deathsInEncounter", format = "number", latest = true },
	{ id = "kangaroo", metric = "jumps", better = "high", tieKey = "jumps", format = "number", latest = true },
}

-- LooserPiml needs at least this many confirmed ranked duels: nobody gets
-- the title without a fight.
Leaderboard.LOOSERPIML_MIN_DUELS = 3

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
	elseif metric == "rankedWins" then
		return participant.rankedWins
	elseif metric == "level" then
		return participant.level
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

-- participant.at (values computed outside the aggregate, e.g. rankedWins)
-- first, then the aggregate's timestamps. nil if unknown.
local function achievedAt(participant, tieKey)
	local at = tieKey and participant.at and participant.at[tieKey]
	return at or (tieKey and participant.agg and participant.agg.at and participant.agg.at[tieKey]) or nil
end

-- Sorts entries ({ participant, value }) best first: by value, then who got
-- there earlier (latest: later), then by name so the order is always the
-- same. Unknown times count as "later" for fame, "earlier" for shame, so a
-- known time decides.
local function sortEntries(entries, better, tieKey, latest)
	local unknown = latest and -math.huge or math.huge
	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			if better == "low" then
				return a.value < b.value
			end
			return a.value > b.value
		end
		local atA = achievedAt(a.participant, tieKey) or unknown
		local atB = achievedAt(b.participant, tieKey) or unknown
		if atA ~= atB then
			if latest then
				return atA > atB
			end
			return atA < atB
		end
		return a.participant.name < b.participant.name
	end)
end

local function findAward(id)
	return find(Leaderboard.AWARDS, id) or find(Leaderboard.SHAME, id)
end

-- The LooserPiml: last place of the all-time duel ladder among players
-- with at least LOOSERPIML_MIN_DUELS confirmed ranked duels.
-- { name, class, isSelf, value = { wins, losses } } or nil.
function Leaderboard.LooserPiml(participants, merged)
	local rows = Stats.Ladder.Rows(participants or {}, merged)
	for i = #rows, 1, -1 do
		local row = rows[i]
		if row.wins + row.losses >= Leaderboard.LOOSERPIML_MIN_DUELS then
			return { name = row.name, class = row.class, isSelf = row.isSelf, value = { row.wins, row.losses } }
		end
	end
	return nil
end

-- Winner of one award or nil ("No one yet"). Zero never wins a "high"
-- award: nobody is Death King with 0 deaths.
function Leaderboard.Award(participants, awardOrId)
	local award = type(awardOrId) == "table" and awardOrId or findAward(awardOrId)
	if award.special == "looserPiml" then
		return Leaderboard.LooserPiml(participants)
	end
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
	sortEntries(entries, award.better, award.tieKey, award.latest)
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

function Leaderboard.HallOfShame(participants)
	local cards = {}
	for _, award in ipairs(Leaderboard.SHAME) do
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
	elseif format == "record" then
		return string.format("%d – %d", value[1], value[2]) -- ranked wins – losses
	elseif format == "money" then
		return ns.Util.FormatMoney(value)
	elseif format == "duration" then
		return ns.Util.FormatDuration(value)
	end
	return tostring(math.floor(value + 0.5))
end
