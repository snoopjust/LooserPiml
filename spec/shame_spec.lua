local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

-- participant with counters { key = { value, at } } and extra fields
local function p(Model, name, counters, extra)
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

-- duel data for a list of confirmed ranked duels { winner, loser }
local function withDuels(participants, duels)
	local byName = {}
	for _, part in ipairs(participants) do
		byName[part.name] = part
		part.duel = part.duel or { r = {}, h = {} }
	end
	for i, d in ipairs(duels) do
		table.insert(byName[d[1]].duel.r, { i = "d" .. i, t = i, o = d[2], w = true })
		table.insert(byName[d[2]].duel.r, { i = "d" .. i, t = i, o = d[1], w = false })
	end
	return participants
end

-- winner challenges loser, both pick Ranked
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
	net:Advance(1)
end

local function count(mock, fragment)
	local n = 0
	for _, text in ipairs(H.renderedPlain(mock)) do
		if text:find(fragment, 1, true) then
			n = n + 1
		end
	end
	return n
end

describe("Hall of Shame", function()
	after_each(H.checkClients)

	describe("awards", function()
		local Leaderboard, Model
		before_each(function()
			local _, ns = H.client()
			Leaderboard, Model = stats({ ns = ns }).Leaderboard, stats({ ns = ns }).Model
		end)

		it("Broke: least gold right now, 0 counts, non-sharers left out", function()
			local list = {
				p(Model, "Max", nil, { gold = 5000 }),
				p(Model, "Lena", nil, { gold = 0 }),
				p(Model, "Kim"), -- doesn't share gold
			}
			local broke = Leaderboard.Award(list, "broke")
			assert.are.equal("Lena", broke.name)
			assert.are.equal(0, broke.value)
		end)

		it("Noob: lowest level", function()
			local list = { p(Model, "Max", nil, { level = 30 }), p(Model, "Jo", nil, { level = 7 }), p(Model, "Kim") }
			assert.are.equal("Jo", Leaderboard.Award(list, "noob").name)
		end)

		it("Slowpoke, Boss Snack, Kangaroo: the most, zero never 'wins', ties go to the latest", function()
			local list = {
				p(Model, "Max", { levelTime = { 7200, 10 }, levelTimeCount = { 1, 10 }, jumps = { 50, 100 }, deathsInEncounter = { 2, 300 } }),
				p(Model, "Lena", { levelTime = { 1800, 10 }, levelTimeCount = { 1, 10 }, jumps = { 50, 200 }, deathsInEncounter = { 2, 100 } }),
				p(Model, "Kim", { jumps = { 0, 0 } }),
			}
			assert.are.equal("Max", Leaderboard.Award(list, "slowpoke").name) -- 2 h per level
			assert.are.equal("Lena", Leaderboard.Award(list, "kangaroo").name) -- same jumps, got there later
			assert.are.equal("Max", Leaderboard.Award(list, "bossSnack").name) -- same, later
			assert.is_nil(Leaderboard.Award({ p(Model, "Kim") }, "kangaroo"))
		end)

		it("LooserPiml: last of the duel ladder among players with at least 3 ranked duels", function()
			local list = withDuels({ p(Model, "Max"), p(Model, "Lena"), p(Model, "Jo") }, {
				{ "Max", "Lena" }, { "Max", "Lena" }, { "Lena", "Max" }, { "Max", "Jo" }, { "Lena", "Jo" },
			})
			-- Max 3-1, Lena 2-2, Jo 0-2 (only 2 duels: not eligible)
			local looser = Leaderboard.Award(list, "looserPiml")
			assert.are.equal("Lena", looser.name)
			assert.are.same({ 2, 2 }, looser.value)
			assert.are.equal("2 – 2", Leaderboard.Format(looser.value, "record"))
			assert.is_nil(Leaderboard.LooserPiml(withDuels({ p(Model, "A"), p(Model, "B") }, { { "A", "B" } })))
			assert.are.equal(6, #Leaderboard.HallOfShame(list))
		end)
	end)

	describe("tab", function()
		it("switches between Fame and Shame with six cards for Shame", function()
			local mock, ns = H.client({ testMode = true })
			stats(mock):FillSampleFriends()
			mock:Advance(2)
			ns.Window:Open("leaderboard")
			local frame = ns.Window.frame.tabFrames.leaderboard
			assert.is_true(H.hasText(frame, "Hall of Fame"))
			assert.is_false(frame.cards[6].shown)
			frame.hallButtons[2]:Click()
			assert.are.equal("shame", stats(mock).LeaderboardTab.hall)
			assert.is_true(frame.hallButtons[2].selected)
			assert.is_true(H.hasText(frame, "Hall of Shame"))
			for _, label in ipairs({ "Broke", "Noob", "LooserPiml", "Slowpoke", "Boss Snack", "Kangaroo" }) do
				assert.is_true(H.hasText(frame, label), label)
			end
			assert.is_true(frame.cards[6].shown)
			assert.are.equal(116, frame.cards[6].width) -- six cards share the width
			-- sample duels: Kim is last of the ladder with 1 – 2
			assert.is_true(H.hasText(frame, "1 – 2 ranked"))
			frame.hallButtons[1]:Click()
			assert.is_true(H.hasText(frame, "Duel King"))
			assert.are.equal(140, frame.cards[5].width)
			assert.is_false(frame.cards[6].shown)
		end)

		it("shows the LooserPiml badge on the PvP ladder and in the minimap tooltip", function()
			local mock, ns = H.client({ testMode = true })
			stats(mock):FillSampleFriends()
			mock:Advance(2)
			assert.are.equal("Kim-TestRealm", stats(mock).Titles.holder)
			ns.Window:Open("pvp")
			local frame = ns.Window.frame.tabFrames.pvp
			local kimRow
			for _, row in ipairs(frame.ladderRows) do
				if row.name.text_ and H.stripColors(row.name.text_):find("^Kim") then
					kimRow = H.stripColors(row.name.text_)
				end
			end
			assert.are.equal("Kim LooserPiml", (kimRow:gsub("%s+", " ")))
			local tooltip = mock.env.GameTooltip
			tooltip:ClearLines()
			ns.Window:FillTooltip(tooltip)
			local found = false
			for _, line in ipairs(tooltip.lines) do
				if H.stripColors(line) == "LooserPiml: Kim" then
					found = true
				end
			end
			assert.is_true(found)
		end)
	end)

	describe("between friends", function()
		it("announces a new LooserPiml once a duel made it so, on both sides, and shows the badge in the Friends tab", function()
			local clients, net = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			for _ = 1, 3 do
				rankedDuel(net, me, max)
			end
			net:Advance(35) -- both sides' stats arrive
			assert.are.equal(1, count(me, "Max is the new LooserPiml!"))
			assert.are.equal(1, count(max, "Max is the new LooserPiml!"))
			assert.are.equal("Max-TestRealm", stats(me).Titles.holder)
			me.ns.Window:Open("friends")
			assert.is_true(H.hasText(me.ns.Window.frame.tabFrames.friends, "LooserPiml"))
			-- the tables turn: four wins for Max, Me is last (3 – 4)
			for _ = 1, 4 do
				rankedDuel(net, max, me)
			end
			net:Advance(35)
			assert.are.equal(1, count(me, "Me is the new LooserPiml!"))
			assert.are.equal(1, count(max, "Me is the new LooserPiml!"))
			-- more stats messages without a change: no repeat
			stats(max):Changed()
			net:Advance(35)
			assert.are.equal(1, count(me, "Me is the new LooserPiml!"))
		end)

		it("doesn't announce after /reload (the title is remembered)", function()
			local clients, net = H.friends({ { name = "Me" }, { name = "Max" } })
			local me, max = clients[1], clients[2]
			for _ = 1, 3 do
				rankedDuel(net, me, max)
			end
			net:Advance(35)
			local reloaded = H.client({ name = "Me", savedVariables = me.env.LooserPimlDB }) -- Max is in the saved list
			reloaded:Advance(5)
			assert.are.equal(0, count(reloaded, "LooserPiml!"))
			assert.are.equal("Max-TestRealm", stats(reloaded).Titles.holder)
		end)

		it("follows 'Ranked duel results' and has a simulation", function()
			local mock, ns = H.client({ testMode = true })
			ns.Slash:Dispatch("sim looserpiml Kim")
			mock:Advance(1)
			assert.is_truthy(H.lastRendered(mock):find("[test] Kim is the new LooserPiml!", 1, true))
			ns:GetModule("Ticker").db.show.duelRanked = false
			local before = #mock.rendered
			ns.Slash:Dispatch("sim looserpiml Jo")
			mock:Advance(6)
			assert.are.equal(before, #mock.rendered)
			assert.are.equal(0, #mock.sent)
		end)
	end)
end)
