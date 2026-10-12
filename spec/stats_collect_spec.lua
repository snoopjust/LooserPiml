local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

local function events(mock, eventType)
	local out = {}
	for _, e in ipairs(stats(mock):GetChar().log) do
		if not eventType or e.type == eventType then
			out[#out + 1] = e
		end
	end
	return out
end

local function last(mock, eventType)
	local list = events(mock, eventType)
	return list[#list]
end

local function today(mock)
	return stats(mock):GetAggregates().tonight
end

local function setMoney(mock, amount)
	mock.money = amount
	mock:Fire("PLAYER_MONEY")
end

describe("Stats collectors", function()
	after_each(H.checkClients)

	describe("core events", function()
		it("records a death with zone, level, instance and drowned flags", function()
			local mock = H.client()
			mock:Fire("MIRROR_TIMER_START", "BREATH", 1000, 180000, -1, 0, "Breath")
			mock:Advance(3)
			mock.player.dead = true
			mock:Fire("PLAYER_DEAD")
			local e = last(mock, "death")
			assert.are.equal("Elwynn Forest", e.zone)
			assert.are.equal(10, e.level)
			assert.is_false(e.inInstance)
			assert.is_true(e.data.drowned)
			assert.is_number(e.t)
			assert.are.equal(1, today(mock).n.deaths)
			assert.are.equal(1, today(mock).n.drowned)
		end)

		it("records level-ups with played time; the level seen from the start is complete", function()
			local mock = H.client()
			mock:Advance(600)
			mock.player.level = 11
			mock:Fire("PLAYER_LEVEL_UP", 11)
			local first = last(mock, "level_up")
			assert.are.equal(11, first.data.level)
			assert.is_nil(first.data.complete) -- we joined level 10 half-way
			mock:Advance(1200)
			mock.player.level = 12
			mock:Fire("PLAYER_LEVEL_UP", 12)
			local second = last(mock, "level_up")
			assert.is_true(second.data.complete)
			assert.is_true(math.abs(second.data.played - 1200) <= 2, "played " .. tostring(second.data.played))
			local Model = stats(mock).Model
			assert.is_true(math.abs(Model.AverageLevelTime(today(mock)) - 1200) <= 2)
		end)

		it("records instance enter/leave for every instance type, boss kills and wipes", function()
			local mock = H.client()
			mock:EnterInstance("Warsong Gulch", "pvp", 489)
			mock:LeaveInstance()
			mock:EnterInstance("The Deadmines", "party", 36)
			mock:Fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
			mock:Fire("ENCOUNTER_END", 2, "Cookie", 1, 5, 0)
			local instances = events(mock, "instance")
			assert.are.equal(3, #instances)
			assert.are.equal("pvp", instances[1].data.itype)
			assert.are.equal("leave", instances[2].data.action)
			assert.are.equal(1, today(mock).n.dungeons)
			assert.are.equal("Edwin VanCleef", events(mock, "encounter")[1].data.name)
			assert.are.equal(1, today(mock).n.bossKills)
			assert.are.equal(1, today(mock).n.bossWipes)
			mock:Advance(3) -- enter/leave banners wait a moment for friends doing the same
			assert.are.equal(1, #mock.rendered) -- the Ticker announced the dungeon, not the battleground
		end)

		it("never records simulated bosses or simulated deaths", function()
			local mock, ns = H.client({ testMode = true })
			ns.Slash:Dispatch("sim boss")
			mock:Advance(15)
			ns.Slash:Dispatch("sim death")
			ns.Slash:Dispatch("sim levelup")
			assert.are.equal(0, #events(mock, "encounter"))
			assert.are.equal(0, #events(mock, "death"))
			assert.are.equal(0, #events(mock, "level_up"))
		end)

		it("records quests with their XP and money reward", function()
			local mock = H.client()
			mock:Fire("QUEST_TURNED_IN", 176, 450, 1200)
			setMoney(mock, mock.money + 1200)
			local quest = last(mock, "quest_done")
			assert.are.same({ id = 176, xp = 450, money = 1200 }, quest.data)
			assert.are.equal("quest", last(mock, "money").data.source)
			assert.are.equal(1, today(mock).n.quests)
		end)
	end)

	describe("money sources", function()
		it("classifies by hint first, then by the open window", function()
			local classify = stats(H.client()).ClassifyMoney
			assert.are.equal("repair", classify(-100, "repair", { merchant = true }))
			assert.are.equal("vendor_sell", classify(100, nil, { merchant = true }))
			assert.are.equal("vendor_buy", classify(-100, nil, { merchant = true }))
			assert.are.equal("loot", classify(100, nil, { loot = true, merchant = true }))
			assert.are.equal("trainer", classify(-100, nil, { trainer = true }))
			assert.are.equal("flight", classify(-100, nil, { taxi = true }))
			assert.are.equal("other", classify(100, nil, {}))
		end)

		it("tracks merchant, repair, loot (with grace after closing), mail and AH mail", function()
			local mock, ns = H.client()
			local money = mock.money
			mock:Fire("MERCHANT_SHOW")
			money = money + 500
			setMoney(mock, money)
			money = money - 200
			setMoney(mock, money)
			mock.env.RepairAllItems(false)
			money = money - 300
			setMoney(mock, money)
			mock:Fire("MERCHANT_CLOSED")
			mock:Advance(3)
			money = money + 5
			setMoney(mock, money)

			mock:Fire("LOOT_OPENED", true, false)
			money = money + 100
			setMoney(mock, money)
			mock:Fire("LOOT_CLOSED")
			money = money + 50 -- arrives just after the window closed
			setMoney(mock, money)

			mock:Fire("MAIL_SHOW")
			mock.invoices[1] = "seller"
			mock.env.TakeInboxMoney(1)
			money = money + 10000
			setMoney(mock, money)
			mock.env.TakeInboxMoney(2)
			money = money + 7
			setMoney(mock, money)
			mock:Fire("MAIL_CLOSED")

			local sources = {}
			for _, e in ipairs(events(mock, "money")) do
				sources[#sources + 1] = e.data.source .. ":" .. e.data.delta
			end
			assert.are.same({
				"vendor_sell:500", "vendor_buy:-200", "repair:-300", "other:5",
				"loot:100", "loot:50", "ah_mail:10000", "mail:7",
			}, sources)
			local agg = today(mock)
			assert.are.equal(150, agg.n.moneyLooted)
			assert.are.equal(300, agg.moneyOut.repair)
			assert.is_true(#mock.calls >= 3) -- Blizzard's functions still ran (post-hooks)
			assert.are.equal(ns, mock.ns)
		end)
	end)

	describe("travel", function()
		it("records a zone/subzone once, flights with destination, and the hearthstone", function()
			local mock = H.client()
			local first = #events(mock, "travel")
			assert.is_true(first >= 1) -- the login zone counts as visited
			mock.subzone = "Lion's Pride Inn"
			mock:Fire("ZONE_CHANGED")
			mock.subzone = "Goldshire"
			mock:Fire("ZONE_CHANGED")
			mock.subzone = "Lion's Pride Inn"
			mock:Fire("ZONE_CHANGED")
			assert.are.equal(first + 1, #events(mock, "travel"))
			assert.are.equal("Lion's Pride Inn", last(mock, "travel").data.subzone)

			mock.taxiNodes[3] = "Stormwind, Elwynn"
			mock:Fire("TAXIMAP_OPENED")
			mock.env.TakeTaxiNode(3)
			setMoney(mock, mock.money - 50)
			assert.are.equal("Stormwind, Elwynn", last(mock, "travel").data.to)
			assert.are.equal("flight", last(mock, "money").data.source)

			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8690)
			assert.are.equal("hearth", last(mock, "travel").data.kind)
			assert.are.equal(1, today(mock).n.hearths)
		end)
	end)

	describe("fun counters", function()
		it("counts ground jumps only, and food/drink by localized spell name", function()
			local mock = H.client()
			local jump = mock.env.JumpOrAscendStart
			jump()
			jump()
			mock.swimming = true
			jump()
			mock.swimming = false
			mock.falling = true
			jump()
			mock.falling = false
			assert.are.equal(2, today(mock).n.jumps)

			mock.spellNames[1131] = "Food" -- a different food item, same spell name
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 1131)
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 430)
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-4", 433) -- not us
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", H.Mock.Secret())
			assert.are.equal(1, today(mock).n.food)
			assert.are.equal(1, today(mock).n.drink)
			assert.are.equal(0, #events(mock, "fun")) -- counters, not log entries
		end)
	end)

	describe("group time", function()
		it("counts time grouped, in total and per LooserPiml friend (handshake answered)", function()
			local mock = H.client({ group = { { name = "Max", class = "WARRIOR" }, { name = "Bob", class = "MAGE" } }, confirmed = { "Max" } })
			mock:Advance(130)
			local agg = today(mock)
			assert.is_true(agg.n.groupSeconds >= 120, tostring(agg.n.groupSeconds))
			assert.is_true(agg.groupWith["Max-TestRealm"] >= 120)
			assert.is_nil(agg.groupWith["Bob-TestRealm"]) -- not a LooserPiml friend
		end)
	end)

	describe("loot and professions", function()
		local blue = "|cff0070dd|Hitem:2140::::::::10:::::::|h[Carving Knife]|h|r"
		local epic = "|cnIQ4:|Hitem:868::::::::10:::::::|h[Ardent Custodian]|h|r"
		local grey = "|cff9d9d9d|Hitem:2211::::::::10:::::::|h[Bat Ear]|h|r"

		it("records own rare-or-better loot with quality, never others' loot", function()
			local mock = H.client()
			mock.itemQuality[blue] = 3 -- from the item API
			mock:Fire("CHAT_MSG_LOOT", "You receive loot: " .. blue .. ".", "Me")
			mock:Fire("CHAT_MSG_LOOT", "You receive loot: " .. epic .. "x2.", "Me") -- quality from the link marker
			mock:Fire("CHAT_MSG_LOOT", "You receive loot: " .. grey .. ".", "Me")
			mock:Fire("CHAT_MSG_LOOT", "Max receives loot: " .. epic .. ".", "Max")
			local loot = events(mock, "loot_rare")
			assert.are.equal(2, #loot)
			assert.are.equal(3, loot[1].data.quality)
			assert.are.equal(4, loot[2].data.quality)
			assert.are.equal(2, loot[2].data.count)
			assert.are.equal(1, today(mock).n.lootEpic)
		end)

		local function loot(mock, guid)
			mock.lootSource[1] = guid
			mock:Fire("LOOT_OPENED", true, false)
			mock:Fire("LOOT_CLOSED")
		end

		it("records crafted items, gathering (herb, ore, skinning, fishing) and not mobs", function()
			local mock = H.client()
			mock:Fire("CHAT_MSG_LOOT", "You create: " .. grey .. "x5.", "Me")
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366) -- Herb Gathering
			loot(mock, "GameObject-0-1-2-3-1617-0000")
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 2575) -- Mining
			loot(mock, "GameObject-0-1-2-3-1731-0000")
			loot(mock, "Creature-0-1-2-3-299-0000") -- a mob
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 8613) -- Skinning the mob
			loot(mock, "Creature-0-1-2-3-299-0000")
			mock.fishing = true
			loot(mock, "GameObject-0-1-2-3-35591-0000")
			local agg = today(mock)
			assert.are.equal(5, agg.n.crafted)
			assert.are.equal(4, agg.n.gathered)
			assert.is_nil(agg.n.chestsOpened)
			local sources = {}
			for _, e in ipairs(events(mock, "profession")) do
				if e.data.kind == "gathered" then
					sources[#sources + 1] = e.data.source
				end
			end
			assert.are.same({ "herb", "mining", "skinning", "fishing" }, sources)
		end)

		it("counts chests separately (chestsOpened), never as gathered", function()
			local mock = H.client()
			loot(mock, "GameObject-0-1-2-3-2843-0000") -- a chest: no gathering cast before it
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
			mock:Advance(10) -- too long ago for the next loot window
			loot(mock, "GameObject-0-1-2-3-2844-0000")
			mock.lootSlots = { { isQuestItem = true } } -- a quest object on the ground, not a chest
			loot(mock, "GameObject-0-1-2-3-2845-0000")
			local agg = today(mock)
			assert.are.equal(2, agg.n.chestsOpened)
			assert.is_nil(agg.n.gathered)
			assert.are.equal(0, #events(mock, "profession")) -- a counter, not log entries
		end)

		it("does not guess when the cast before the loot window was secret", function()
			local mock = H.client()
			mock:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", H.Mock.Secret())
			loot(mock, "GameObject-0-1-2-3-1617-0000")
			local agg = today(mock)
			assert.is_nil(agg.n.gathered)
			assert.is_nil(agg.n.chestsOpened)
			H.assertNoErrors(mock)
		end)

		it("records skill-ups and tells professions from other skills", function()
			local mock = H.client()
			mock:Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 75.")
			mock:Fire("CHAT_MSG_SKILL", "Your skill in Defense has increased to 14.")
			mock:Fire("CHAT_MSG_SKILL", H.Mock.Secret()) -- chat lockdown
			local skills = events(mock, "profession")
			assert.are.equal(2, #skills)
			assert.are.same({ kind = "skillup", skill = "Mining", rank = 75, profession = true }, skills[1].data)
			assert.is_false(skills[2].data.profession)
			assert.are.equal(1, today(mock).n.professionSkillUps)
			assert.are.equal(2, today(mock).n.skillUps)
		end)
	end)

	describe("pvp", function()
		it("records only own duels with result, opponent and whether they run LooserPiml", function()
			local mock = H.client({ confirmed = { "Max" } })
			mock:Fire("CHAT_MSG_SYSTEM", "Me has defeated Max in a duel")
			mock:Fire("CHAT_MSG_SYSTEM", "Me has fled from Bob in a duel")
			mock:Fire("CHAT_MSG_SYSTEM", "Bob has fled from Me in a duel")
			mock:Fire("CHAT_MSG_SYSTEM", "Kim has defeated Lena in a duel") -- not ours
			mock:Fire("CHAT_MSG_SYSTEM", H.Mock.Secret())
			local duels = events(mock, "duel")
			assert.are.equal(3, #duels)
			assert.are.same({ result = "won", opponent = "Max-TestRealm", opponentHasAddon = true }, duels[1].data)
			assert.are.equal("fled", duels[2].data.result)
			assert.are.equal("opponent_fled", duels[3].data.result)
			assert.is_false(duels[3].data.opponentHasAddon)
			local agg = today(mock)
			assert.are.equal(2, agg.n.duelsWon)
			assert.are.equal(1, agg.n.duelsLost)
			assert.are.equal(1, agg.n.duelsFled)
		end)

		it("records battleground joined, finished (with own score) and left early", function()
			local mock = H.client()
			mock:EnterInstance("Warsong Gulch", "pvp", 489)
			mock.scores = {
				{ name = "Enemy-Other", faction = 0, killingBlows = 9 },
				{ name = "Me", faction = 1, killingBlows = 4, honorableKills = 12, deaths = 3, honorGained = 250 },
			}
			mock:Fire("PVP_MATCH_COMPLETE", 1, 900)
			mock:LeaveInstance()
			mock:EnterInstance("Arathi Basin", "pvp", 529)
			mock:LeaveInstance() -- before the match ended: deserter
			local pvp = events(mock, "pvp")
			assert.are.equal("joined", pvp[1].data.kind)
			assert.are.equal("finished", pvp[2].data.kind)
			assert.is_true(pvp[2].data.won)
			assert.are.equal(4, pvp[2].data.killingBlows)
			assert.are.equal(250, pvp[2].data.honorGained)
			assert.are.equal("deserted", pvp[4].data.kind)
			local agg = today(mock)
			assert.are.equal(1, agg.n.bgWon)
			assert.are.equal(1, agg.n.bgDeserted)
			assert.are.equal(2, agg.n.bgJoined)
		end)

		it("skips secret scoreboard values and still records the match", function()
			local mock = H.client()
			mock:EnterInstance("Warsong Gulch", "pvp", 489)
			mock.scores = { { name = "Me", faction = 1, killingBlows = H.Mock.Secret() } }
			mock:Fire("PVP_MATCH_COMPLETE", 0, 600)
			local finished = last(mock, "pvp")
			assert.is_false(finished.data.won)
			assert.is_nil(finished.data.killingBlows)
		end)

		it("snapshots honor only when it changes", function()
			local mock = H.client()
			mock:Fire("HONOR_XP_UPDATE", "player") -- unchanged from the login baseline
			mock.honor = 180
			mock:Fire("HONOR_XP_UPDATE", "player")
			local honor = events(mock, "pvp")
			assert.are.equal(1, #honor)
			assert.are.equal(180, honor[1].data.honor)
			assert.are.equal(180, today(mock).last.honor.v)
		end)
	end)

	describe("settings and storage", function()
		it("records nothing while 'collect stats' is off", function()
			local mock = H.client()
			local before = #events(mock)
			stats(mock).db.collect = false
			mock:Fire("PLAYER_DEAD")
			mock.env.JumpOrAscendStart()
			mock:Fire("QUEST_TURNED_IN", 1, 10, 10)
			assert.are.equal(before, #events(mock))
			assert.is_nil(today(mock).n.jumps)
		end)

		it("compacts old events into daily buckets on login", function()
			local now = 1760000000
			local saved = {
				schemaVersion = 1,
				modules = { Stats = { chars = { ["Me-TestRealm"] = {
					log = {
						{ t = now - 40 * 86400, type = "death", data = {} },
						{ t = now - 3600, type = "death", data = {} },
					},
					buckets = {},
				} } } },
			}
			local mock = H.client({ savedVariables = saved })
			local char = stats(mock):GetChar()
			local deaths = 0
			for _, e in ipairs(char.log) do
				if e.type == "death" then
					deaths = deaths + 1
				end
			end
			assert.are.equal(1, deaths)
			assert.are.equal(2, stats(mock):GetAggregates().all.n.deaths)
		end)

		it("keeps each character's log separate", function()
			local saved = { schemaVersion = 1, modules = { Stats = { chars = {
				["Alt-TestRealm"] = { log = { { t = 1, type = "death", data = {} } }, buckets = {} },
			} } } }
			local mock = H.client({ savedVariables = saved })
			assert.are.equal(0, #events(mock, "death"))
		end)
	end)
end)
