-- Duel ladder data provider: merges both duelists' own records into
-- confirmed ranked duels, the ladder rows and the head to head matrix.
-- Pure Lua (no game API), like Leaderboard.lua; PvPTab.lua only draws it.
--
-- Input: participants (Sync.lua GetParticipants) with `duel` data
--   { r = { { i = duel id, t = time, o = opponent, w = won }, ... },
--     h = { [opponent] = { w, l, rw, rl } } }
-- Each client records only its own result, so a ranked duel is known from
-- both sides by its shared id:
--   confirmed   both records name each other and exactly one says "won"
--   disputed    both say won (or both lost): left out of the ladder
--   one-sided   the other side's data has no such ranked duel, or the
--               other player isn't a participant here: left out too (it
--               only counts once both sides agree)
local _, ns = ...

local Stats = ns:GetModule("Stats")

local Ladder = {}
Stats.Ladder = Ladder

Ladder.MAX_MATRIX = 7 -- players in the head to head matrix

-- { confirmed = { { id, t, winner, loser } }, disputed = { { id, t, a, b } } }
-- confirmed/disputed are sorted by time (then id).
function Ladder.Merge(participants)
	local claims = {} -- id -> { { name, rec }, ... }
	for _, p in ipairs(participants or {}) do
		local data = p.duel
		if data and type(data.r) == "table" then
			local seen = {}
			for _, rec in ipairs(data.r) do
				if rec.i and not seen[rec.i] then
					seen[rec.i] = true -- one claim per player and duel
					local list = claims[rec.i] or {}
					claims[rec.i] = list
					list[#list + 1] = { name = p.name, rec = rec }
				end
			end
		end
	end
	local confirmed, disputed = {}, {}
	for id, list in pairs(claims) do
		local a, b = list[1], list[2]
		if #list == 2 and a.rec.o == b.name and b.rec.o == a.name then
			local t = math.min(a.rec.t or 0, b.rec.t or 0)
			if a.rec.w ~= b.rec.w then
				local winner, loser = a.name, b.name
				if b.rec.w then
					winner, loser = b.name, a.name
				end
				confirmed[#confirmed + 1] = { id = id, t = t, winner = winner, loser = loser }
			else
				disputed[#disputed + 1] = { id = id, t = t, a = a.name, b = b.name }
			end
		end
	end
	local function byTime(x, y)
		if x.t ~= y.t then
			return x.t < y.t
		end
		return x.id < y.id
	end
	table.sort(confirmed, byTime)
	table.sort(disputed, byTime)
	return { confirmed = confirmed, disputed = disputed }
end

-- "W4", "L2", "—"
function Ladder.StreakText(streak)
	if streak > 0 then
		return "W" .. streak
	elseif streak < 0 then
		return "L" .. -streak
	end
	return "—"
end

-- Per player: wins, losses, current streak and the time of the last win,
-- from confirmed duels (since startTime, if given).
function Ladder.Totals(merged, startTime)
	local totals = {}
	local function entry(name)
		local e = totals[name]
		if not e then
			e = { wins = 0, losses = 0, streak = 0 }
			totals[name] = e
		end
		return e
	end
	for _, duel in ipairs(merged.confirmed) do
		if not startTime or duel.t >= startTime then
			local w, l = entry(duel.winner), entry(duel.loser)
			w.wins = w.wins + 1
			w.streak = w.streak > 0 and w.streak + 1 or 1
			w.lastWin = duel.t
			l.losses = l.losses + 1
			l.streak = l.streak < 0 and l.streak - 1 or -1
		end
	end
	return totals
end

-- Ladder rows (ranked only, players with at least one confirmed duel):
-- sorted by wins, then win rate, then name.
-- { rank, name, class, isSelf, online, wins, losses, rate, streak, streakText }
function Ladder.Rows(participants, merged)
	merged = merged or Ladder.Merge(participants)
	local totals = Ladder.Totals(merged)
	local rows = {}
	for _, p in ipairs(participants or {}) do
		local t = totals[p.name]
		if t and t.wins + t.losses > 0 then
			rows[#rows + 1] = {
				name = p.name, class = p.class, isSelf = p.isSelf, online = p.online,
				wins = t.wins, losses = t.losses, rate = t.wins / (t.wins + t.losses),
				streak = t.streak, streakText = Ladder.StreakText(t.streak),
			}
		end
	end
	table.sort(rows, function(a, b)
		if a.wins ~= b.wins then
			return a.wins > b.wins
		end
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		return a.name < b.name
	end)
	for i, row in ipairs(rows) do
		row.rank = i
	end
	return rows
end

-- Duel King and friends: sets participant.rankedWins (confirmed ranked
-- wins since startTime) and participant.at.rankedWins (the last of those
-- wins, for "the earlier achiever wins" ties). Returns the merge.
function Ladder.Annotate(participants, startTime)
	local merged = Ladder.Merge(participants)
	local totals = Ladder.Totals(merged, startTime)
	for _, p in ipairs(participants) do
		local t = totals[p.name]
		p.rankedWins = t and t.wins or 0
		p.at = p.at or {}
		p.at.rankedWins = t and t.lastWin
	end
	return merged
end

-- How often `a` beat `b` in all duels: a's own record if a sent one,
-- otherwise b's record of losses against a.
local function allWins(byName, a, b)
	local own = byName[a] and byName[a].duel and byName[a].duel.h
	if own then
		local rec = own[b]
		return rec and rec.w or 0
	end
	local other = byName[b] and byName[b].duel and byName[b].duel.h
	local rec = other and other[a]
	return rec and rec.l or 0
end

-- Head to head: rows = winner, columns = opponent, cell = how often the
-- row beat the column. mode "ranked" (confirmed ranked duels) or "all"
-- (everyone's own records of all duels). Players: participants with at
-- least one duel in this mode against another participant, at most
-- MAX_MATRIX (most duels first, then by name).
-- { players = { participant, ... }, cells[i][j] = n (nil on the diagonal),
--   heat[i][j] = 0 | 1 | 2, wins[i], losses[i], max }
function Ladder.Matrix(participants, mode, merged)
	participants = participants or {}
	local byName = {}
	for _, p in ipairs(participants) do
		byName[p.name] = p
	end
	local beats = {} -- beats[a][b]
	local function add(a, b, n)
		if n and n > 0 and byName[a] and byName[b] and a ~= b then
			beats[a] = beats[a] or {}
			beats[a][b] = (beats[a][b] or 0) + n
		end
	end
	if mode == "all" then
		for _, a in ipairs(participants) do
			for _, b in ipairs(participants) do
				if a.name ~= b.name then
					add(a.name, b.name, allWins(byName, a.name, b.name))
				end
			end
		end
	else
		merged = merged or Ladder.Merge(participants)
		for _, duel in ipairs(merged.confirmed) do
			add(duel.winner, duel.loser, 1)
		end
	end
	local involved = {}
	for a, row in pairs(beats) do
		for b, n in pairs(row) do
			involved[a] = (involved[a] or 0) + n
			involved[b] = (involved[b] or 0) + n
		end
	end
	local players = {}
	for _, p in ipairs(participants) do
		if involved[p.name] then
			players[#players + 1] = p
		end
	end
	table.sort(players, function(x, y)
		if involved[x.name] ~= involved[y.name] then
			return involved[x.name] > involved[y.name]
		end
		return x.name < y.name
	end)
	while #players > Ladder.MAX_MATRIX do
		table.remove(players)
	end
	local cells, wins, losses, max = {}, {}, {}, 0
	for i, rowPlayer in ipairs(players) do
		cells[i] = {}
		wins[i], losses[i] = 0, 0
		for j, colPlayer in ipairs(players) do
			if i ~= j then
				local n = beats[rowPlayer.name] and beats[rowPlayer.name][colPlayer.name] or 0
				local lost = beats[colPlayer.name] and beats[colPlayer.name][rowPlayer.name] or 0
				cells[i][j] = n
				wins[i] = wins[i] + n
				losses[i] = losses[i] + lost
				if n > max then
					max = n
				end
			end
		end
	end
	-- "Highlight high values": the top quarter of the matrix strongly, the
	-- upper half lightly.
	local heat = {}
	for i = 1, #players do
		heat[i] = {}
		for j = 1, #players do
			local n = cells[i][j]
			if n and n > 0 and n >= max * 0.75 then
				heat[i][j] = 2
			elseif n and n > 0 and n >= max * 0.4 then
				heat[i][j] = 1
			else
				heat[i][j] = 0
			end
		end
	end
	return { players = players, cells = cells, heat = heat, wins = wins, losses = losses, max = max, mode = mode == "all" and "all" or "ranked" }
end
