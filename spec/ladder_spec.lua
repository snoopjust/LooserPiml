local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

-- Participants with duel data built from a list of ranked duels:
-- { winner, loser [, id] } (both sides' records, as two clients would send).
local function build(duels, extra)
	local data = {}
	local function of(name)
		data[name] = data[name] or { r = {}, h = {} }
		return data[name]
	end
	for i, d in ipairs(duels) do
		local id = d[3] or ("d" .. i)
		table.insert(of(d[1]).r, { i = id, t = 1000 + i, o = d[2], w = true })
		table.insert(of(d[2]).r, { i = id, t = 1000 + i, o = d[1], w = false })
	end
	for _, rec in ipairs(extra or {}) do
		table.insert(of(rec.by).r, rec.rec)
	end
	local participants = {}
	for name, duel in pairs(data) do
		participants[#participants + 1] = { name = name, duel = duel, isSelf = name == "Me" }
	end
	table.sort(participants, function(a, b)
		return a.name < b.name
	end)
	return participants
end

local function rowsByName(rows)
	local out = {}
	for _, row in ipairs(rows) do
		out[row.name] = row
	end
	return out
end

describe("Ranked duels: ladder", function()
	after_each(H.checkClients)

	describe("merge", function()
		it("counts a duel only when both sides agree; conflicting claims are disputed", function()
			local _, ns = H.client()
			local Ladder = stats({ ns = ns }).Ladder
			local participants = build({ { "Max", "Lena" }, { "Lena", "Max" } }, {
				-- both claim the win
				{ by = "Max", rec = { i = "x", t = 2000, o = "Lena", w = true } },
				{ by = "Lena", rec = { i = "x", t = 2000, o = "Max", w = true } },
				-- one-sided: Lena's data has no such ranked duel
				{ by = "Max", rec = { i = "y", t = 2001, o = "Lena", w = true } },
				-- opponent isn't a participant here
				{ by = "Max", rec = { i = "z", t = 2002, o = "Bob", w = true } },
			})
			local merged = Ladder.Merge(participants)
			assert.are.equal(2, #merged.confirmed)
			assert.are.equal(1, #merged.disputed)
			assert.are.equal("x", merged.disputed[1].id)
			local rows = rowsByName(Ladder.Rows(participants, merged))
			assert.are.equal(1, rows.Max.wins)
			assert.are.equal(1, rows.Max.losses)
			assert.are.equal(1, rows.Lena.wins)
		end)

		it("ignores claims that don't name each other", function()
			local _, ns = H.client()
			local Ladder = stats({ ns = ns }).Ladder
			local participants = build({}, {
				{ by = "Max", rec = { i = "q", t = 1, o = "Lena", w = true } },
				{ by = "Lena", rec = { i = "q", t = 1, o = "Jo", w = false } },
				{ by = "Jo", rec = { i = "q", t = 1, o = "Max", w = false } },
			})
			assert.are.equal(0, #Ladder.Merge(participants).confirmed)
		end)
	end)

	describe("rows", function()
		it("sorts by ranked wins, then win rate, with streaks", function()
			local _, ns = H.client()
			local Ladder = stats({ ns = ns }).Ladder
			local participants = build({
				{ "Max", "Lena" }, { "Max", "Lena" }, { "Lena", "Max" }, -- Max 2-1
				{ "Jo", "Kim" }, { "Jo", "Kim" },                       -- Jo 2-0
				{ "Lena", "Kim" }, { "Lena", "Kim" }, { "Lena", "Kim" }, -- Lena 4-2 in total
			})
			local rows = Ladder.Rows(participants)
			local names = {}
			for i, row in ipairs(rows) do
				names[i] = row.name
				assert.are.equal(i, row.rank)
			end
			assert.are.same({ "Lena", "Jo", "Max", "Kim" }, names)
			local by = rowsByName(rows)
			assert.are.equal("W4", by.Lena.streakText) -- won the last four (1 vs Max, 3 vs Kim)
			assert.are.equal("L1", by.Max.streakText)
			assert.are.equal("L5", by.Kim.streakText)
			assert.are.equal(1, by.Jo.rate)
			assert.are.equal(2 / 3, by.Max.rate)
		end)

		it("leaves out players without a confirmed ranked duel", function()
			local _, ns = H.client()
			local Ladder = stats({ ns = ns }).Ladder
			local participants = build({ { "Max", "Lena" } })
			participants[#participants + 1] = { name = "Jo", duel = { r = {}, h = {} } }
			assert.are.equal(2, #Ladder.Rows(participants))
			assert.are.equal("—", Ladder.StreakText(0))
		end)
	end)

	describe("head to head matrix", function()
		it("shows how often the row beat the column, ranked or all duels", function()
			local _, ns = H.client()
			local Ladder = stats({ ns = ns }).Ladder
			local participants = build({ { "Max", "Lena" }, { "Max", "Lena" }, { "Lena", "Max" } })
			-- all duels (own records incl. fun ones)
			participants[1].duel.h = { Max = { w = 3, l = 4, rw = 1, rl = 2 } }      -- Lena
			participants[2].duel.h = { Lena = { w = 4, l = 3, rw = 2, rl = 1 } }     -- Max
			local ranked = Ladder.Matrix(participants, "ranked")
			assert.are.equal("Lena", ranked.players[1].name) -- same number of duels: by name
			assert.is_nil(ranked.cells[1][1])
			assert.are.equal(1, ranked.cells[1][2]) -- Lena beat Max once
			assert.are.equal(2, ranked.cells[2][1])
			assert.are.equal(1, ranked.wins[1])
			assert.are.equal(2, ranked.losses[1])
			assert.are.equal(2, ranked.heat[2][1])
			assert.are.equal(1, ranked.heat[1][2]) -- 1 >= 0.4 * 2
			local all = Ladder.Matrix(participants, "all")
			assert.are.equal("all", all.mode)
			assert.are.equal(3, all.cells[1][2])
			assert.are.equal(4, all.cells[2][1])
			assert.are.equal(4, all.losses[1])
		end)

		it("uses the opponent's record when a player sent none (all duels)", function()
			local _, ns = H.client()
			local Ladder = stats({ ns = ns }).Ladder
			local participants = {
				{ name = "Max", duel = { r = {}, h = { Lena = { w = 2, l = 5, rw = 0, rl = 0 } } } },
				{ name = "Lena" }, -- older client: no duel data
			}
			local all = Ladder.Matrix(participants, "all")
			assert.are.equal(2, #all.players)
			local max = all.players[1].name == "Max" and 1 or 2
			local lena = 3 - max
			assert.are.equal(2, all.cells[max][lena])
			assert.are.equal(5, all.cells[lena][max])
			assert.are.equal(0, #Ladder.Matrix(participants, "ranked").players)
		end)
	end)

	describe("between clients", function()
		local function rankedDuel(net, winner, loser)
			winner:ChallengeToDuel(loser.player.name)
			loser:DuelRequested(winner.player.name)
			net:Advance(1)
			stats(winner).DuelPanel.frame.ranked:Click()
			stats(loser).DuelPanel.frame.ranked:Click()
			loser:AcceptDuelRequest()
			net:Advance(5)
			local text = winner.player.name .. " has defeated " .. loser.player.name .. " in a duel"
			winner:DuelEnded(text)
			loser:DuelEnded(text)
		end

		it("merges both sides after the stats sync, also for a third friend; nobody grouped", function()
			local clients, net = H.friends({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE" } })
			local me, max, lena = clients[1], clients[2], clients[3]
			assert.are.equal(0, #me.group)
			rankedDuel(net, me, max)
			net:Advance(35) -- stats go out at most every 30 s
			for _, mock in ipairs({ me, max, lena }) do
				local s = stats(mock)
				local rows = rowsByName(s.Ladder.Rows(s:GetParticipants("all")))
				assert.are.equal(1, rows["Me-TestRealm"].wins, mock.player.name)
				assert.are.equal(1, rows["Max-TestRealm"].losses, mock.player.name)
				assert.are.equal("W1", rows["Me-TestRealm"].streakText)
			end
			-- before the opponent's data arrives, it doesn't count: Lena's view of
			-- a new duel right after it ended
			rankedDuel(net, max, me)
			local s = stats(lena)
			local rows = rowsByName(s.Ladder.Rows(s:GetParticipants("all")))
			assert.are.equal(0, rows["Max-TestRealm"].wins)
			net:Advance(35)
			rows = rowsByName(s.Ladder.Rows(s:GetParticipants("all")))
			assert.are.equal(1, rows["Max-TestRealm"].wins)
		end)

		it("leaves a disputed duel out of the ladder", function()
			local clients, net = H.friends({ { name = "Me" }, { name = "Max" } })
			local me, max = clients[1], clients[2]
			rankedDuel(net, me, max)
			-- Max's client claims the win for the same duel
			local _, maxRanked = stats(max).Duels:GetRecords()
			maxRanked[1].w = true
			stats(max):Changed()
			net:Advance(35)
			local s = stats(me)
			local participants = s:GetParticipants("all")
			local merged = s.Ladder.Merge(participants)
			assert.are.equal(0, #merged.confirmed)
			assert.are.equal(1, #merged.disputed)
			assert.are.equal(0, #s.Ladder.Rows(participants, merged))
		end)

		it("sends duel data only about listed friends and sanitizes what arrives", function()
			local mock = H.client({ confirmed = { "Max" } })
			local s = stats(mock)
			local records, ranked = s.Duels:GetRecords()
			records["Bob-TestRealm"] = { w = 3, l = 0, rw = 0, rl = 0, s = 0 }
			records["Max-TestRealm"] = { w = 1, l = 0, rw = 1, rl = 0, s = 1 }
			ranked[1] = { i = "abc", t = 5, o = "Max-TestRealm", w = true }
			ranked[2] = { i = "def", t = 6, o = "Bob-TestRealm", w = true }
			local out = s.Duels:ForSync()
			assert.are.equal(1, #out.r)
			assert.is_nil(out.h["Bob-TestRealm"])
			assert.is_not_nil(out.h["Max-TestRealm"])

			local clean = s.Duels.Clean({
				r = {
					{ i = "ok1", t = 10, o = "Max", w = true },
					{ i = "bad id!", t = 10, o = "Max", w = true },
					{ i = "x", t = "soon", o = "Max", w = true },
					{ i = "y", t = 10, o = "|cffff0000Evil|r", w = true },
					{ i = "z", t = 10, o = "Max", w = "yes" },
					"junk",
				},
				h = { Max = { w = -1, l = 1e99, rw = 2.7, rl = "x" }, ["a b"] = { w = 1 }, Lena = 5 },
			})
			assert.are.same({ { i = "ok1", t = 10, o = "Max-TestRealm", w = true } }, clean.r)
			assert.are.same({ ["Max-TestRealm"] = { w = 0, l = 0, rw = 2, rl = 0 } }, clean.h)
			assert.is_nil(s.Duels.Clean("nope"))
		end)

		it("keeps the stats message small with the maximum of ranked duels", function()
			local mock = H.client({ confirmed = { "Maximilian", "Lenalove", "Johannes" } })
			local s = stats(mock)
			local records, ranked = s.Duels:GetRecords()
			local opponents = { "Maximilian-TestRealm", "Lenalove-TestRealm", "Johannes-TestRealm" }
			for i = 1, 200 do
				local o = opponents[i % 3 + 1]
				ranked[i] = { i = string.format("%08x", i * 2654435761 % 4294967296), t = 1760000000 + i * 600, o = o, w = i % 2 == 0 }
				records[o] = { w = 90, l = 80, rw = 70, rl = 60, s = 3 }
			end
			local before = #mock.ns.Comm:Encode({ v = 1, t = "STATS", d = (function()
				local payload = s:BuildSyncPayload()
				payload.duel = nil
				return payload
			end)() })
			local text = mock.ns.Comm:Encode({ v = 1, t = "STATS", d = s:BuildSyncPayload() })
			local chunks = mock.ns.Comm:CountParts(#text)
			print(string.format("\n[size] STATS with 60 ranked duels: %d bytes on the wire (%d without duels), %d parts", #text, before, chunks))
			assert.is_true(chunks <= 10)
		end)

		it("fills sample duels for the fake friends in test mode", function()
			local mock = H.client({ testMode = true })
			local s = stats(mock)
			s:FillSampleFriends()
			local participants = s:GetParticipants("all")
			local merged = s.Ladder.Merge(participants)
			assert.are.equal(12, #merged.confirmed)
			assert.are.equal(1, #merged.disputed)
			assert.are.equal("Max-TestRealm", s.Ladder.Rows(participants, merged)[1].name)
			assert.are.equal(0, #mock.sent)
		end)
	end)
end)
