local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

-- Decoded STATS messages this client handed to the network.
local function statsMessages(mock)
	local out = {}
	for _, call in ipairs(mock.sent) do
		local envelope = mock.ns.Comm:Decode(call.text)
		if envelope and envelope.t == "STATS" then
			out[#out + 1] = envelope
		end
	end
	return out
end

local function die(mock)
	mock.player.dead = true
	mock:Fire("PLAYER_DEAD")
	mock.player.dead = false
	mock:Fire("PLAYER_UNGHOST")
end

describe("Stats sync", function()
	after_each(H.checkClients)

	it("exchanges aggregates on login and after changes, cached per friend", function()
		local clients = H.group({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
		local me, max = clients[1], clients[2]
		me:Advance(5) -- login broadcast (8 s after login)
		local friend = stats(me).db.friends["Max-TestRealm"]
		assert.is_table(friend)
		assert.are.equal("WARRIOR", friend.class)
		assert.is_table(friend.stats.all)

		die(max)
		die(max)
		me:Advance(35) -- Max's debounced broadcast
		friend = stats(me).db.friends["Max-TestRealm"]
		assert.are.equal(2, friend.stats.tonight.n.deaths)
		assert.are.equal(2, stats(me):GetFriendAggregate(friend, "tonight").n.deaths)
		H.assertNoErrors(me)
		H.assertNoErrors(max)
	end)

	it("broadcasts at most once per 30 s, however many changes happen", function()
		local mock = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
		mock:Advance(5)
		local before = #statsMessages(mock)
		for _ = 1, 10 do
			mock.env.JumpOrAscendStart()
			mock:Advance(1)
		end
		mock:Advance(30)
		local sent = #statsMessages(mock) - before
		assert.is_true(sent >= 1 and sent <= 2, "sent " .. sent)
	end)

	it("sends nothing at all with 'share my stats' off, but still receives", function()
		local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
		stats(mock).db.share = false
		mock.sent = {}
		die(mock)
		mock:Advance(60)
		mock:JoinGroup({ { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE" } })
		mock:Advance(60)
		assert.are.equal(0, #statsMessages(mock))

		local payload = { mv = 1, day = "x", week = "y", class = "MAGE", p = { all = { n = { deaths = 4 } } } }
		local text = ns.Comm:Encode({ v = 1, t = "STATS", s = 3, id = 1, d = payload })
		mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Lena-TestRealm")
		assert.are.equal(4, stats(mock).db.friends["Lena-TestRealm"].stats.all.n.deaths)
	end)

	it("treats a friend's 'tonight'/'week' from an earlier day/week as empty", function()
		local mock = H.client()
		local Model = stats(mock).Model
		local now = GetServerTime and GetServerTime() or mock.env.GetServerTime()
		local friend = {
			day = "2001-01-01",
			week = Model.WeekKey(now),
			stats = {
				tonight = { n = { deaths = 5 } },
				week = { n = { deaths = 7 } },
				all = { n = { deaths = 9 } },
			},
		}
		local s = stats(mock)
		assert.are.equal(0, Model.Get(s:GetFriendAggregate(friend, "tonight"), "deaths"))
		assert.are.equal(7, Model.Get(s:GetFriendAggregate(friend, "week"), "deaths"))
		assert.are.equal(9, Model.Get(s:GetFriendAggregate(friend, "all"), "deaths"))
		friend.week = "2001-01-01"
		assert.are.equal(0, Model.Get(s:GetFriendAggregate(friend, "week"), "deaths"))
	end)

	it("keeps friends in SavedVariables, so they show up offline after a reload", function()
		local clients = H.group({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
		local me = clients[1]
		me:Advance(5)
		local saved = me.env.LooserPimlDB
		local mock2 = H.client({ savedVariables = saved })
		local participants = stats(mock2):GetParticipants("all")
		local max
		for _, p in ipairs(participants) do
			if p.name == "Max-TestRealm" then
				max = p
			end
		end
		assert.is_table(max)
		assert.is_false(max.online)
		assert.is_number(max.lastSeen)
	end)

	it("sanitizes garbage and hostile payloads", function()
		local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
		local function send(data, id)
			local text = ns.Comm:Encode({ v = 1, t = "STATS", s = 9, id = id, d = data })
			mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Max-TestRealm")
		end
		send("nope", 1)
		send({ p = "nope" }, 2)
		send({ class = "|cffff0000X", level = 1e9, p = { all = { n = { deaths = -5, quests = 3 } } } }, 3)
		local friend = stats(mock).db.friends["Max-TestRealm"]
		assert.are.equal("WARRIOR", friend.class) -- from the roster, the bogus class was dropped
		assert.is_nil(friend.level)
		assert.are.same({ quests = 3 }, friend.stats.all.n)
		H.assertNoErrors(mock)
	end)

	it("holds stats during a boss fight and sends only the newest snapshot afterwards", function()
		local mock = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
		mock:Advance(40)
		mock.sent = {}
		mock:StartEncounter()
		die(mock)
		mock:Advance(35)
		die(mock)
		mock:Advance(35)
		assert.are.equal(0, #statsMessages(mock))
		local queued = 0
		for _, entry in ipairs(mock.ns.Comm.queue) do
			if entry.t == "STATS" then
				queued = queued + 1
			end
		end
		assert.are.equal(1, queued)
		mock:EndEncounter()
		mock:Advance(5)
		local messages = statsMessages(mock)
		assert.are.equal(1, #messages)
		assert.are.equal(2, messages[1].d.p.tonight.n.deaths)
	end)

	it("keeps the message small: a busy evening fits in a few chunks", function()
		local mock = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
		for i = 1, 30 do
			die(mock)
			mock:Fire("QUEST_TURNED_IN", i, 100, 100)
			mock.money = mock.money + 777
			mock:Fire("PLAYER_MONEY")
			mock.env.JumpOrAscendStart()
		end
		local text = mock.ns.Comm:Encode({ v = 1, t = "STATS", d = stats(mock):BuildSyncPayload() })
		assert.is_true(#text < 4 * 254, "STATS message is " .. #text .. " bytes")
	end)

	describe("sample friends (test mode)", function()
		it("fills fake friends for the leaderboard, only in test mode, never saved", function()
			local mock = H.client()
			assert.is_false(stats(mock):FillSampleFriends())
			mock.ns.TestMode:Enable()
			assert.is_true(stats(mock):FillSampleFriends())
			local participants = stats(mock):GetParticipants("tonight")
			assert.are.equal(5, #participants) -- me + Max, Lena, Jo, Kim
			assert.are.same({}, stats(mock).db.friends)
			mock.ns.TestMode:Disable()
			assert.are.equal(1, #stats(mock):GetParticipants("tonight"))
		end)
	end)
end)
