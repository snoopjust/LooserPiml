local H = require("helpers")

describe("Leaderboard provider", function()
	after_each(H.checkClients)

	local Leaderboard, Model

	before_each(function()
		local _, ns = H.client()
		local stats = ns:GetModule("Stats")
		Leaderboard, Model = stats.Leaderboard, stats.Model
	end)

	-- participant with counters { key = { value, achievedAt } }
	local function p(name, counters, extra)
		local agg = Model.Empty()
		for key, spec in pairs(counters or {}) do
			Model.Add(agg, key, spec[1], spec[2])
		end
		local participant = { name = name, class = "WARRIOR", agg = agg }
		for k, v in pairs(extra or {}) do
			participant[k] = v
		end
		return participant
	end

	describe("awards", function()
		it("crowns the Death King and Fish Food by the highest value", function()
			local list = {
				p("Max", { deaths = { 3, 100 }, drowned = { 1, 100 } }),
				p("Lena", { deaths = { 5, 200 } }),
				p("Me", { deaths = { 1, 50 } }, { isSelf = true }),
			}
			assert.are.equal("Lena", Leaderboard.Award(list, "deathKing").name)
			assert.are.equal(5, Leaderboard.Award(list, "deathKing").value)
			assert.are.equal("Max", Leaderboard.Award(list, "fishFood").name)
		end)

		it("gives Gold Hoarder to the most gold on hand right now, not gold looted; non-sharers are left out", function()
			local list = {
				p("Max", { moneyLooted = { 900000, 100 } }, { gold = 5000 }),  -- looted a lot, spent it
				p("Lena", { moneyLooted = { 100, 100 } }, { gold = 120000 }),
				p("Kim", nil, { gold = nil }),                                  -- doesn't share gold
				p("Me", nil, { isSelf = true, gold = 0 }),
			}
			local winner = Leaderboard.Award(list, "goldHoarder")
			assert.are.equal("Lena", winner.name)
			assert.are.equal(120000, winner.value)
			assert.is_nil(Leaderboard.Award({ p("Kim"), p("Me", nil, { gold = 0 }) }, "goldHoarder")) -- zero never wins
			local tie = Leaderboard.Award({ p("Zed", nil, { gold = 7 }), p("Abe", nil, { gold = 7 }) }, "goldHoarder")
			assert.are.equal("Abe", tie.name)
		end)

		it("gives Speedrunner to the lowest average time per level", function()
			local list = {
				p("Max", { levelTime = { 7200, 10 }, levelTimeCount = { 2, 10 } }), -- 1 h per level
				p("Lena", { levelTime = { 5400, 10 }, levelTimeCount = { 3, 10 } }), -- 30 min per level
				p("Kim"), -- never finished a level while recording: not eligible
			}
			local winner = Leaderboard.Award(list, "speedrunner")
			assert.are.equal("Lena", winner.name)
			assert.are.equal(1800, winner.value)
		end)

		it("lets the earlier achiever win a tie, then sorts by name", function()
			local list = {
				p("Max", { deaths = { 4, 300 } }),
				p("Lena", { deaths = { 4, 100 } }), -- reached 4 deaths first
				p("Jo", { deaths = { 2, 50 } }),
			}
			assert.are.equal("Lena", Leaderboard.Award(list, "deathKing").name)
			local sameTime = { p("Zed", { deaths = { 1, 5 } }), p("Abe", { deaths = { 1, 5 } }) }
			assert.are.equal("Abe", Leaderboard.Award(sameTime, "deathKing").name)
		end)

		it("shows 'No one yet' (nil) when nobody qualifies, and never crowns a zero", function()
			assert.is_nil(Leaderboard.Award({}, "deathKing"))
			assert.is_nil(Leaderboard.Award({ p("Max"), p("Lena", { quests = { 3, 1 } }) }, "deathKing"))
			assert.is_nil(Leaderboard.Award({ p("Max") }, "speedrunner"))
			local cards = Leaderboard.HallOfFame({})
			assert.are.equal(5, #cards)
			for _, card in ipairs(cards) do
				assert.is_nil(card.winner)
			end
		end)

		it("crowns the Duel King by confirmed ranked wins in the selected period", function()
			local mock, ns = H.client({ testMode = true })
			local stats = ns:GetModule("Stats")
			local Ladder = stats.Ladder
			local now = mock.env.GetServerTime()
			local function duels(list)
				local data = {}
				for i, d in ipairs(list) do
					local id, t = "d" .. i, d[3]
					data[d[1]] = data[d[1]] or { r = {}, h = {} }
					data[d[2]] = data[d[2]] or { r = {}, h = {} }
					table.insert(data[d[1]].r, { i = id, t = t, o = d[2], w = true })
					table.insert(data[d[2]].r, { i = id, t = t, o = d[1], w = d[4] == "disputed" })
				end
				return data
			end
			-- Max won 3 last week, Lena 2 tonight (one more disputed)
			local tonight, lastWeek = stats.Model.DayStart(now) + 60, now - 10 * 86400
			local data = duels({
				{ "Max", "Lena", lastWeek }, { "Max", "Lena", lastWeek + 1 }, { "Max", "Jo", lastWeek + 2 },
				{ "Lena", "Jo", tonight }, { "Lena", "Max", tonight + 1 }, { "Lena", "Jo", tonight + 2, "disputed" },
			})
			local function list(period)
				local out = {}
				for _, name in ipairs({ "Max", "Lena", "Jo" }) do
					out[#out + 1] = { name = name, duel = data[name] }
				end
				Ladder.Annotate(out, stats.Model.PeriodStart(period, now))
				return out
			end
			local allTime = Leaderboard.Award(list("all"), "duelKing")
			assert.are.equal("Max", allTime.name)
			assert.are.equal(3, allTime.value)
			local tonightKing = Leaderboard.Award(list("tonight"), "duelKing")
			assert.are.equal("Lena", tonightKing.name)
			assert.are.equal(2, tonightKing.value) -- the disputed one doesn't count
			assert.is_nil(Leaderboard.Award({ { name = "Kim", rankedWins = 0 } }, "duelKing"))
			-- tie on wins: whoever got there first
			local tie = { { name = "Zed", rankedWins = 2, at = { rankedWins = 50 } }, { name = "Abe", rankedWins = 2, at = { rankedWins = 90 } } }
			assert.are.equal("Zed", Leaderboard.Award(tie, "duelKing").name)
			-- sample friends: the Hall of Fame card has a winner
			stats:FillSampleFriends()
			local king = Leaderboard.Award(stats:GetParticipants("all"), "duelKing")
			assert.are.equal("Max-TestRealm", king.name)
		end)
	end)

	describe("ranking", function()
		it("sorts descending with rank, bar fraction relative to the leader, everyone listed", function()
			local list = {
				p("Max", { quests = { 5, 10 } }),
				p("Lena", { quests = { 10, 10 } }),
				p("Me", nil, { isSelf = true }),
			}
			local rows, metric = Leaderboard.Ranking(list, "quests")
			assert.are.equal("quests", metric.id)
			assert.are.same({ "Lena", "Max", "Me" }, { rows[1].name, rows[2].name, rows[3].name })
			assert.are.same({ 1, 2, 3 }, { rows[1].rank, rows[2].rank, rows[3].rank })
			assert.are.equal(1, rows[1].fraction)
			assert.are.equal(0.5, rows[2].fraction)
			assert.are.equal(0, rows[3].fraction)
			assert.is_true(rows[3].isSelf)
		end)

		it("handles all-zero and empty lists", function()
			local rows = Leaderboard.Ranking({ p("Max"), p("Lena") }, "quests")
			assert.are.equal(0, rows[1].fraction)
			assert.are.same({}, (Leaderboard.Ranking({}, "deaths")))
		end)

		it("ranks 'Gold' by current gold, highest first, listing only friends who share it", function()
			local list = {
				p("Max", { moneyLooted = { 999999, 1 } }, { gold = 2500 }),
				p("Lena", nil, { gold = 10000 }),
				p("Kim"), -- doesn't share gold
				p("Me", nil, { isSelf = true, gold = 5000 }),
			}
			local rows, metric = Leaderboard.Ranking(list, "gold")
			assert.is_true(metric.snapshot)
			assert.are.same({ "Lena", "Me", "Max" }, { rows[1].name, rows[2].name, rows[3].name })
			assert.are.equal(3, #rows)
			assert.are.equal(0.5, rows[2].fraction)
			assert.are.equal("1g", Leaderboard.Format(rows[1].value, metric.format))
		end)

		it("formats values per metric", function()
			assert.are.equal("1g 50s", Leaderboard.Format(15000, "money"))
			assert.are.equal("30m", Leaderboard.Format(1800, "duration"))
			assert.are.equal("7", Leaderboard.Format(7, "number"))
			assert.are.equal("-", Leaderboard.Format(nil, "number"))
		end)
	end)

	describe("with real data", function()
		it("ranks a friend's synced aggregates against my own", function()
			local clients = H.group({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			for _ = 1, 3 do
				max.player.dead = true
				max:Fire("PLAYER_DEAD")
				max.player.dead = false
				max:Fire("PLAYER_UNGHOST")
			end
			me:Advance(40)
			local stats = me.ns:GetModule("Stats")
			local winner = stats.Leaderboard.Award(stats:GetParticipants("tonight"), "deathKing")
			assert.are.equal("Max-TestRealm", winner.name)
			assert.are.equal(3, winner.value)
			assert.are.equal("WARRIOR", winner.class)
		end)
	end)
end)
