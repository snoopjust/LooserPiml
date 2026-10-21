local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

local function duels(mock)
	return stats(mock).Duels
end

local function panel(mock)
	return stats(mock).DuelPanel
end

local function panelText(mock)
	return table.concat(H.texts(panel(mock).frame), " | ")
end

local function click(mock, choice)
	panel(mock).frame[choice]:Click()
end

-- Me and Max: connected LooserPiml friends, NOT grouped.
local function pair()
	local clients, net = H.friends({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
	return clients[1], clients[2], net
end

-- `a` challenges `b` (b gets the game's dialog and DUEL_REQUESTED).
local function challenge(a, b, net)
	a:ChallengeToDuel(b.player.name)
	b:DuelRequested(a.player.name)
	net:Advance(1)
end

local function duelMessages(mock)
	local out = {}
	for _, msg in ipairs(H.decodedSent(mock)) do
		if msg.t == "DUEL" then
			out[#out + 1] = msg
		end
	end
	return out
end

-- Both sides see the same result line.
local function finish(net, clients, text)
	for _, mock in ipairs(clients) do
		mock:DuelEnded(text)
	end
	net:Advance(1)
end

describe("Ranked duels: handshake", function()
	after_each(H.checkClients)

	it("opens the panel on both sides, below the game's dialog for the challenged player", function()
		local me, max, net = pair()
		challenge(me, max, net)
		assert.is_true(panel(me):IsShown())
		assert.is_true(panel(max):IsShown())
		assert.is_true(panel(max).frame.anchoredToDialog)
		assert.is_false(panel(me).frame.anchoredToDialog) -- the challenger has no dialog: center
		local text = panelText(max)
		assert.is_truthy(text:find("LooserPiml · ranked duel?", 1, true))
		assert.is_truthy(text:find("Your ranked record against Me: 0 – 0", 1, true))
		assert.is_truthy(text:find("Ranked", 1, true))
		assert.is_truthy(text:find("Just for fun", 1, true))
		assert.is_truthy(text:find("LooserPiml never does that for you", 1, true))
		-- both sides share the duel id from the challenged side
		assert.is_string(duels(max).current.id)
		assert.are.equal(duels(max).current.id, duels(me).current.id)
	end)

	it("counts the duel as ranked when both picked Ranked", function()
		local me, max, net = pair()
		challenge(me, max, net)
		click(me, "ranked")
		net:Advance(1)
		assert.is_truthy(panelText(me):find("You picked Ranked · waiting for Max…", 1, true))
		assert.is_truthy(panelText(max):find("Me picked Ranked", 1, true))
		click(max, "ranked")
		net:Advance(1)
		assert.is_truthy(panelText(me):find("You both picked Ranked", 1, true))
		max:AcceptDuelRequest()
		net:Advance(1)
		assert.is_true(panel(me):IsShown()) -- still open during the countdown
		net:Advance(3)
		assert.is_false(panel(me):IsShown())
		assert.is_false(panel(max):IsShown())
		finish(net, { me, max }, "Me has defeated Max in a duel")

		local mine = duels(me):GetRecord("Max-TestRealm")
		local theirs = duels(max):GetRecord("Me-TestRealm")
		assert.are.same({ w = 1, l = 0, rw = 1, rl = 0, s = 1 }, mine)
		assert.are.same({ w = 0, l = 1, rw = 0, rl = 1, s = -1 }, theirs)
		local _, myRanked = duels(me):GetRecords()
		local _, maxRanked = duels(max):GetRecords()
		assert.are.equal(1, #myRanked)
		assert.are.equal(myRanked[1].i, maxRanked[1].i)
		assert.is_true(myRanked[1].w)
		assert.is_false(maxRanked[1].w)
		assert.is_nil(duels(me).current) -- the choice expired with the result
		local log = stats(me):GetChar().log
		assert.is_true(log[#log].data.ranked)
		assert.are.equal(1, stats(me):GetAggregates().all.n.rankedWon)
		assert.are.equal(1, stats(max):GetAggregates().all.n.rankedLost)
	end)

	it("is just for fun when one side picks Just for fun", function()
		local me, max, net = pair()
		challenge(me, max, net)
		click(me, "ranked")
		click(max, "fun")
		net:Advance(1)
		assert.is_truthy(panelText(me):find("Max picked Just for fun", 1, true))
		max:AcceptDuelRequest()
		net:Advance(5)
		finish(net, { me, max }, "Me has defeated Max in a duel")
		assert.are.same({ w = 1, l = 0, rw = 0, rl = 0, s = 0 }, duels(me):GetRecord("Max-TestRealm"))
		assert.are.same({ w = 0, l = 1, rw = 0, rl = 0, s = 0 }, duels(max):GetRecord("Me-TestRealm"))
		local _, ranked = duels(me):GetRecords()
		assert.are.equal(0, #ranked)
	end)

	it("is not ranked when the opponent never answers", function()
		local me, max, net = pair()
		challenge(me, max, net)
		click(me, "ranked")
		max:AcceptDuelRequest()
		net:Advance(5)
		finish(net, { me, max }, "Max has defeated Me in a duel")
		assert.are.same({ w = 0, l = 1, rw = 0, rl = 0, s = 0 }, duels(me):GetRecord("Max-TestRealm"))
	end)

	it("counts fleeing as a loss for whoever fled", function()
		local me, max, net = pair()
		challenge(me, max, net)
		click(me, "ranked")
		click(max, "ranked")
		max:AcceptDuelRequest()
		net:Advance(5)
		finish(net, { me, max }, "Max has fled from Me in a duel")
		assert.are.same({ w = 1, l = 0, rw = 1, rl = 0, s = 1 }, duels(me):GetRecord("Max-TestRealm"))
		assert.are.same({ w = 0, l = 1, rw = 0, rl = 1, s = -1 }, duels(max):GetRecord("Me-TestRealm"))
	end)

	it("keeps a ranked streak per opponent", function()
		local me, max, net = pair()
		for _, text in ipairs({ "Me has defeated Max in a duel", "Me has defeated Max in a duel", "Max has defeated Me in a duel", "Max has defeated Me in a duel" }) do
			challenge(me, max, net)
			click(me, "ranked")
			click(max, "ranked")
			max:AcceptDuelRequest()
			net:Advance(5)
			finish(net, { me, max }, text)
		end
		assert.are.same({ w = 2, l = 2, rw = 2, rl = 2, s = -2 }, duels(me):GetRecord("Max-TestRealm"))
		assert.are.same({ w = 2, l = 2, rw = 2, rl = 2, s = 2 }, duels(max):GetRecord("Me-TestRealm"))
	end)

	it("closes both panels when the request is declined; the choice is gone", function()
		local me, max, net = pair()
		challenge(me, max, net)
		click(me, "ranked")
		click(max, "ranked")
		net:Advance(1)
		max:CancelDuelRequest()
		me:Fire("DUEL_FINISHED")
		net:Advance(1)
		assert.is_false(panel(me):IsShown())
		assert.is_false(panel(max):IsShown())
		assert.is_nil(duels(me).current)
		assert.is_nil(duels(max).current)
		-- a later result (another duel, no new handshake) is not ranked
		finish(net, { me, max }, "Me has defeated Max in a duel")
		assert.are.equal(0, duels(me):GetRecord("Max-TestRealm").rw)
	end)

	it("lets the choice expire after the duel ends without a result line", function()
		local me, max, net = pair()
		challenge(me, max, net)
		click(me, "ranked")
		click(max, "ranked")
		max:AcceptDuelRequest()
		net:Advance(5)
		me:Fire("DUEL_FINISHED")
		max:Fire("DUEL_FINISHED")
		net:Advance(6)
		assert.is_nil(duels(me).current)
		me:Fire("CHAT_MSG_SYSTEM", "Me has defeated Max in a duel")
		assert.are.equal(0, duels(me):GetRecord("Max-TestRealm").rw)
	end)

	it("leaves duels to the death alone (no panel, no message)", function()
		local me, max, net = pair()
		me:UserAction(function()
			me.env.StartDuel("Max", true, true) -- Blizzard's death-duel confirm dialog
		end)
		max:Fire("DUEL_TO_THE_DEATH_REQUESTED", "Me")
		net:Advance(1)
		assert.is_false(panel(me):IsShown() == true)
		assert.is_false(panel(max):IsShown() == true)
		assert.are.equal(0, #duelMessages(me))
		assert.are.equal(0, #duelMessages(max))
	end)

	it("opens the challenger's panel from the friend's ask when the hook missed the request", function()
		local me, max, net = pair()
		max:DuelRequested("Me") -- Me challenged through a path our hook didn't see
		net:Advance(1)
		assert.is_true(panel(me):IsShown())
		assert.are.equal(duels(max).current.id, duels(me).current.id)
		assert.are.equal("challenger", duels(me).current.role)
	end)

	it("never shows a panel or sends anything for a duel with someone who isn't a connected friend", function()
		local me, max, net = pair()
		me:ChallengeToDuel("Bob")
		me:DuelRequested("Bob")
		net:Advance(1)
		assert.is_false(panel(me):IsShown() == true)
		assert.are.equal(0, #duelMessages(me))
		finish(net, { me }, "Me has defeated Bob in a duel")
		local log = stats(me):GetChar().log
		assert.are.equal("duel", log[#log].type)
		assert.is_nil(log[#log].data.ranked)
		-- listed but offline: not connected either
		max.online = false
		me.friendList.Max = { connected = false }
		me:Fire("FRIENDLIST_UPDATE")
		net:Advance(1)
		me:DuelRequested("Max")
		net:Advance(1)
		assert.is_false(panel(me):IsShown() == true)
		assert.are.equal(0, #duelMessages(me))
	end)

	it("sends the choice only to the opponent, as a whisper, also with other friends online", function()
		local clients, net = H.friends({ { name = "Me" }, { name = "Max" }, { name = "Lena" } })
		local me, max, lena = clients[1], clients[2], clients[3]
		challenge(me, max, net)
		click(me, "ranked")
		net:Advance(1)
		local sent = duelMessages(me)
		assert.is_true(#sent >= 1)
		for _, msg in ipairs(sent) do
			assert.are.equal("WHISPER", msg.chatType)
			assert.are.equal("Max", msg.target)
		end
		assert.is_false(panel(lena):IsShown() == true)
	end)

	it("with 'Ask ranked?' off: no panel, and the challenger's panel says so", function()
		local me, max, net = pair()
		stats(max).db.askRanked = false
		challenge(me, max, net)
		assert.is_false(panel(max):IsShown() == true)
		assert.is_true(panel(me):IsShown())
		assert.is_truthy(panelText(me):find("Max doesn't ask for ranked duels", 1, true))
		click(me, "ranked")
		max:AcceptDuelRequest()
		net:Advance(5)
		finish(net, { me, max }, "Me has defeated Max in a duel")
		assert.are.equal(0, duels(me):GetRecord("Max-TestRealm").rw)
	end)

	it("never calls a duel action or touches Blizzard's dialog itself", function()
		local me, max, net = pair()
		-- every path: challenge, picks, accept, result; decline; withdraw; sim
		challenge(me, max, net)
		click(me, "ranked")
		click(max, "fun")
		click(max, "ranked")
		max:AcceptDuelRequest()
		net:Advance(5)
		finish(net, { me, max }, "Me has defeated Max in a duel")
		challenge(me, max, net)
		max:CancelDuelRequest()
		net:Advance(1)
		challenge(max, me, net)
		max:CancelDuelRequest()
		me:Fire("DUEL_FINISHED")
		net:Advance(130)
		for _, mock in ipairs({ me, max }) do
			H.assertNoGameActions(mock)
			for _, call in ipairs(mock.calls) do
				if call.name:find("Duel") then
					assert.is_true(call.user, call.name .. " was called by LooserPiml")
				end
			end
		end
		-- the dialog stayed untouched (only the player's own accept closed it)
		max:DuelRequested("Me")
		net:Advance(1)
		click(max, "ranked")
		click(max, "fun")
		assert.is_not_nil(max.visiblePopups.DUEL_REQUESTED)
		H.assertNoGameActions(max)
	end)

	it("/lp sim duel opens the panel with a fake friend and sends nothing", function()
		local mock, ns = H.client({ testMode = true })
		ns.Slash:Dispatch("sim duel Max ranked")
		assert.is_true(panel(mock):IsShown())
		assert.is_truthy(panelText(mock):find("[test]", 1, true))
		mock:Advance(1.5)
		assert.is_truthy(panelText(mock):find("Max picked Ranked", 1, true))
		click(mock, "ranked")
		mock:Advance(10)
		assert.is_false(panel(mock):IsShown())
		assert.are.equal(0, #mock.sent)
		-- simulated duels are never recorded
		assert.are.equal(0, duels(mock):GetRecord("Max-TestRealm").w)
	end)

	it("/lp sim duel waits for your pick before the duel starts", function()
		local mock, ns = H.client({ testMode = true })
		ns.Slash:Dispatch("sim duel Max ranked")
		mock:Advance(20) -- read the panel at leisure
		assert.is_true(panel(mock):IsShown())
		assert.is_false(duels(mock).current.accepted == true)
		click(mock, "ranked")
		mock:Advance(1.5)
		assert.is_true(panel(mock):IsShown()) -- accepted 2 s after the pick ...
		mock:Advance(4)
		assert.is_false(panel(mock):IsShown()) -- ... closed after the 3 s countdown
		local before = #mock.rendered
		mock:Advance(2)
		assert.are.equal(before + 1, #mock.rendered)
		assert.is_truthy(H.lastRendered(mock):find("won a ranked duel against Max", 1, true))
		-- never picking: it goes on by itself after 30 s, just for fun
		ns.Slash:Dispatch("sim duel Lena ranked")
		mock:Advance(40)
		assert.is_false(panel(mock):IsShown())
		assert.are.equal(before + 1, #mock.rendered)
	end)

	it("puts the status line right below the note", function()
		local mock, ns = H.client({ testMode = true })
		ns.Slash:Dispatch("sim duel Max ranked")
		local frame = panel(mock).frame
		local point, relativeTo, relativePoint = frame.status:GetPoint(1)
		assert.are.equal("TOPLEFT", point)
		assert.are.equal(frame.note, relativeTo)
		assert.are.equal("BOTTOMLEFT", relativePoint)
	end)
end)
