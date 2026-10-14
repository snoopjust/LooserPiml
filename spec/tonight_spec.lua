local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

local function die(mock)
	mock.player.dead = true
	mock:Fire("PLAYER_DEAD")
	mock.player.dead = false
	mock:Fire("PLAYER_UNGHOST")
end

local function texts(frame)
	return table.concat(H.texts(frame), "\n")
end

describe("Tonight", function()
	after_each(H.checkClients)

	it("sums KPIs over me and my friends who are not grouped, and shows their events in the timeline", function()
		local clients = H.friends({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
		local me, max = clients[1], clients[2]
		die(max)
		die(max)
		die(me)
		max:Fire("PLAYER_LEVEL_UP", 11)
		me:Advance(40)
		local totals = stats(me).Tonight.Totals(stats(me):GetParticipants("tonight"))
		assert.are.equal(3, totals.deaths)
		assert.are.equal(1, totals.levelUps)
		me.ns.Window:Open("tonight")
		local frame = me.ns.Window.frame.tabFrames.tonight
		local all = texts(frame)
		assert.is_true(all:find("Max died", 1, true) ~= nil)
		assert.is_true(all:find("Me died", 1, true) ~= nil)
		assert.is_true(all:find("Max reached level 11!", 1, true) ~= nil)
		local tiles = {}
		for _, tile in ipairs(frame.tiles) do
			tiles[tile.kpi] = tile.value.text_
		end
		assert.are.equal("3", tiles.deaths)
		assert.are.equal("1", tiles.levelUps)
		assert.is_truthy(tiles.session:find("^%d+s$") or tiles.session:find("m"), tiles.session)
		assert.is_true(all:find("Death King\nMax 2", 1, true) ~= nil) -- recap card
		-- newest at the bottom
		local lines = {}
		for _, line in ipairs(frame.lines) do
			if line.shown then
				lines[#lines + 1] = H.stripColors(line.text_)
			end
		end
		assert.is_truthy(lines[#lines]:find("Max reached level 11!", 1, true))
	end)

	it("only shows what happened since 06:00, and keeps the timeline across a reload", function()
		local mock = H.client()
		local now = GetServerTime and GetServerTime() or mock.env.GetServerTime()
		local dayStart = stats(mock).Model.DayStart(now)
		mock.ns.Timeline:Add({ t = dayStart - 60, s = "Max-TestRealm", k = "death", x = "Max died last night." })
		mock.ns.Timeline:Add({ t = dayStart + 60, s = "Max-TestRealm", k = "death", x = "Max died this evening." })
		local saved = mock.env.LooserPimlDB
		local mock2 = H.client({ savedVariables = saved })
		mock2.ns.Window:Open("tonight")
		local all = texts(mock2.ns.Window.frame.tabFrames.tonight)
		assert.is_true(all:find("Max died this evening.", 1, true) ~= nil)
		assert.is_nil(all:find("Max died last night.", 1, true))
	end)

	it("drops timeline entries older than 7 days", function()
		local mock = H.client()
		local now = mock.env.GetServerTime()
		mock.ns.Timeline:Add({ t = now - 8 * 86400, k = "death", x = "old" })
		mock.ns.Timeline:Add({ t = now - 86400, k = "death", x = "recent" })
		mock.ns.Timeline:Prune(now)
		assert.are.equal(1, #mock.ns.Timeline:GetDB())
		assert.are.equal("recent", mock.ns.Timeline:GetDB()[1].x)
	end)

	describe("evening recap", function()
		-- Saved data of a client that was active yesterday (3 deaths, 1 level-up).
		local function savedFromYesterday()
			local mock = H.client()
			local s = stats(mock)
			local now = mock.env.GetServerTime()
			local yesterday = now - 86400
			local log = s:GetChar().log
			for i = 1, 3 do
				log[#log + 1] = { t = yesterday + i, type = "death", data = {} }
			end
			log[#log + 1] = { t = yesterday + 10, type = "level_up", data = { level = 9 } }
			s.db.lastActiveDay = s.Model.DayKey(yesterday)
			s.db.recapShownFor = nil
			return mock.env.LooserPimlDB, s.Model.DayKey(yesterday)
		end

		it("shows last evening's recap once, on the first login of the new day", function()
			local saved, dayKey = savedFromYesterday()
			local mock = H.client({ savedVariables = saved })
			mock:Advance(12)
			local frame = stats(mock).recapFrame
			assert.is_table(frame)
			assert.is_true(frame.shown)
			local all = texts(frame)
			assert.is_true(all:find("Last evening", 1, true) ~= nil)
			assert.is_true(all:find("Death King: Me (3)", 1, true) ~= nil)
			assert.is_true(all:find("Deaths 3 · Level-ups 1", 1, true) ~= nil)
			assert.are.equal(dayKey, mock.env.LooserPimlDB.modules.Stats.recapShownFor)
			assert.are.equal(0, #mock.sent) -- local only
			for _, line in ipairs(mock.chat) do
				assert.is_nil(line:find("Last evening", 1, true)) -- not in chat either
			end

			local again = H.client({ savedVariables = mock.env.LooserPimlDB })
			again:Advance(12)
			assert.is_nil(stats(again).recapFrame) -- once per evening
		end)

		it("can be turned off", function()
			local saved = savedFromYesterday()
			saved.modules.Stats.showRecap = false
			local mock = H.client({ savedVariables = saved })
			mock:Advance(12)
			assert.is_nil(stats(mock).recapFrame)
		end)

		it("stays quiet after an evening without anything to report", function()
			local mock = H.client()
			local s = stats(mock)
			s.db.lastActiveDay = s.Model.DayKey(mock.env.GetServerTime() - 86400)
			local mock2 = H.client({ savedVariables = mock.env.LooserPimlDB })
			mock2:Advance(12)
			assert.is_nil(stats(mock2).recapFrame)
		end)
	end)
end)
