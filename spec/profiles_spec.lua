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

-- { ["Section/Label"] = value }
local function flatten(sections)
	local out = {}
	for _, section in ipairs(sections) do
		for _, row in ipairs(section.rows) do
			out[section.title .. "/" .. row[1]] = row[2]
		end
	end
	return out
end

describe("Profiles", function()
	after_each(H.checkClients)

	it("maps a profile into the seven sections and shows '—' where there is no data", function()
		local s = stats(H.client())
		local Model = s.Model
		local agg = Model.Empty()
		Model.Add(agg, "deaths", 7, 1)
		Model.Add(agg, "drowned", 2, 1)
		Model.Add(agg, "quests", 31, 1)
		Model.Add(agg, "playedSeconds", 5400, 1)
		Model.Add(agg, "lootRare", 3, 1)
		agg.moneyIn.ah_mail = 125000
		agg.moneyOut.repair = 4321
		local view = flatten(s.Profiles.Sections({
			name = "Max-TestRealm", level = 23, agg = agg, gold = 716000,
			prof = { { n = "Mining", r = 75 }, { n = "Herbalism" } }, fav = "Westfall", eve = 6,
		}))
		assert.are.equal("23", view["Progress/Level"])
		assert.are.equal("1h 30m", view["Progress/Time played"])
		assert.are.equal("31", view["Progress/Quests"])
		assert.are.equal("—", view["Progress/Avg time per level"])
		assert.are.equal("7", view["Deaths/Total"])
		assert.are.equal("2", view["Deaths/Drowned"])
		assert.are.equal("—", view["Deaths/First to die in a dungeon"])
		assert.are.equal("71g 60s", view["Loot & gold/Gold on hand"])
		assert.are.equal("12g 50s", view["Loot & gold/Earned at the auction house"])
		assert.are.equal("43s 21c", view["Loot & gold/Spent on repairs"])
		assert.are.equal("3 / 0", view["Loot & gold/Rare / epic items"])
		assert.are.equal("Mining 75, Herbalism", view["Professions/Professions"])
		assert.are.equal("Westfall", view["Travel/Favourite zone"])
		assert.are.equal("—", view["PvP/Rank"])
		assert.are.equal("—", view["PvP/All duels won / lost"])
		assert.are.equal("—", view["PvP/Ranked duels won / lost"])
		assert.are.equal("6", view["Social/Evenings played"])
		Model.Add(agg, "duelsWon", 5, 1)
		Model.Add(agg, "duelsLost", 2, 1)
		Model.Add(agg, "rankedWon", 3, 1)
		local pvp = flatten(s.Profiles.Sections({ name = "Max-TestRealm", agg = agg }))
		assert.are.equal("5 / 2", pvp["PvP/All duels won / lost"])
		assert.are.equal("3 / 0", pvp["PvP/Ranked duels won / lost"])
		-- a friend on an older LooserPiml: no extras, empty aggregate
		local old = flatten(s.Profiles.Sections({ name = "Old-TestRealm" }))
		for key, value in pairs(old) do
			assert.are.equal("—", value, key)
		end
	end)

	it("syncs professions, favourite zone and evenings to friends who are not grouped", function()
		local clients = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
		local me, max = clients[1], clients[2]
		max.zone = "Westfall"
		max:Fire("ZONE_CHANGED_NEW_AREA")
		die(max)
		max:Advance(40)
		local profile
		for _, p in ipairs(stats(me):GetProfiles()) do
			if p.name == "Max-TestRealm" then
				profile = p
			end
		end
		assert.is_table(profile)
		assert.are.equal(10, profile.level)
		assert.are.same({ { n = "Mining" }, { n = "Herbalism" } }, profile.prof)
		assert.are.equal("Westfall", profile.fav)
		assert.are.equal(1, profile.eve)
		assert.are.equal("1", flatten(stats(me).Profiles.Sections(profile))["Deaths/Total"])
	end)

	it("drops hostile profile extras", function()
		local s = stats(H.client())
		local prof, fav, eve = s.CleanProfileExtras({
			prof = { { n = "|cffff0000Evil|r", r = 1e9 }, "junk", { n = "" }, { n = "Mining", r = 75.5 } },
			fav = string.rep("x", 200), eve = -3,
		})
		assert.are.same({ { n = "||cffff0000Evil||r" }, { n = "Mining", r = 75 } }, prof)
		assert.are.equal(64, #fav)
		assert.is_nil(eve)
	end)

	it("counts 'first to die in a dungeon' only when no friend died before me in that visit", function()
		local clients = H.group({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
		local me, max = clients[1], clients[2]
		me:Advance(40)
		for _, c in ipairs(clients) do
			c.zone = "The Deadmines"
			c:EnterInstance("The Deadmines", "party", 36)
		end
		me:Advance(5)
		die(max) -- Max first
		me:Advance(3)
		die(me)
		me:Advance(3)
		local today = stats(me):GetAggregates().tonight.n
		assert.is_nil(today.firstDeaths)
		assert.are.equal(1, stats(max):GetAggregates().tonight.n.firstDeaths)
		for _, c in ipairs(clients) do
			c:LeaveInstance()
		end
		me:Advance(20 * 60)
		me:EnterInstance("Wailing Caverns", "party", 43)
		me:Advance(5)
		die(me)
		assert.are.equal(1, stats(me):GetAggregates().tonight.n.firstDeaths)
	end)

	it("counts played time quietly, without a stats message every minute", function()
		local mock = H.client({ confirmed = { "Max" }, group = { { name = "Max", class = "WARRIOR" } } })
		mock:Advance(40)
		local before = 0
		for _, m in ipairs(H.decodedSent(mock)) do
			if m.t == "STATS" then
				before = before + 1
			end
		end
		mock:Advance(5 * 60)
		local after = 0
		for _, m in ipairs(H.decodedSent(mock)) do
			if m.t == "STATS" then
				after = after + 1
			end
		end
		assert.are.equal(before, after)
		assert.is_true(stats(mock):GetAggregates().tonight.n.playedSeconds >= 290)
	end)

	it("tab: lists me and my friends with level, and shows the selected player's sections", function()
		local mock = H.client({ testMode = true })
		stats(mock):FillSampleFriends()
		mock.ns.Window:Open("profiles")
		local frame = mock.ns.Window.frame.tabFrames.profiles
		assert.is_true(H.hasText(frame, "One player in depth: everything LooserPiml has recorded"))
		local names = {}
		for _, button in ipairs(frame.players) do
			if button.shown then
				names[#names + 1] = H.stripColors(button.label.text_)
			end
		end
		assert.are.equal("Me Lv 10", names[1])
		assert.is_true(table.concat(names, "|"):find("Max Lv 24", 1, true) ~= nil)
		assert.is_true(H.hasText(frame, "Me (you)"))
		frame.players[3]:Click()
		assert.is_true(H.hasText(frame, "Professions"))
		assert.is_true(H.hasText(frame, "Evenings played"))
		assert.is_false(H.hasText(frame, "Me (you)"))
		mock.ns.TestMode:Disable()
	end)
end)
