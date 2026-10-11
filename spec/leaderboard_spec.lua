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
		it("crowns the Death King, Fish Food and Gold Hoarder by the highest value", function()
			local list = {
				p("Max", { deaths = { 3, 100 }, drowned = { 1, 100 }, moneyLooted = { 500, 100 } }),
				p("Lena", { deaths = { 5, 200 }, moneyLooted = { 9000, 200 } }),
				p("Me", { deaths = { 1, 50 } }, { isSelf = true }),
			}
			assert.are.equal("Lena", Leaderboard.Award(list, "deathKing").name)
			assert.are.equal(5, Leaderboard.Award(list, "deathKing").value)
			assert.are.equal("Max", Leaderboard.Award(list, "fishFood").name)
			assert.are.equal("Lena", Leaderboard.Award(list, "goldHoarder").name)
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
			assert.are.equal(4, #cards)
			for _, card in ipairs(cards) do
				assert.is_nil(card.winner)
			end
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
			local rows = Leaderboard.Ranking({ p("Max"), p("Lena") }, "gold")
			assert.are.equal(0, rows[1].fraction)
			assert.are.same({}, (Leaderboard.Ranking({}, "deaths")))
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
