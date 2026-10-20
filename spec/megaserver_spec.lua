local H = require("helpers")

-- WoW: Forever megaserver: characters have a first name and a surname.
-- As seen in-game (2026-10-20): UnitName returns the surname in the realm
-- slot (also for the player), addon senders arrive as "First Surname", a
-- whisper to "First-Surname" is delivered, and the two players' own realms
-- differ ("ClassicBetaPvE" / "ClassicBetaPvE2").

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

-- Partick Kneadmetal and Headdleonty Kneadmetal (the same surname by
-- chance, as in the real test) or another surname for the friend, grouped
-- like in the real test.
local function megaPair(friendSurname)
	friendSurname = friendSurname or "Kneadmetal"
	local net = H.Mock.NewNetwork()
	local me = H.client({
		name = "Partick", surname = "Kneadmetal", realm = "ClassicBetaPvE", class = "MAGE", settle = 0,
		group = { { name = "Headdleonty", realm = friendSurname, class = "PRIEST" } },
	})
	local friend = H.client({
		name = "Headdleonty", surname = friendSurname, realm = "ClassicBetaPvE2", class = "PRIEST", settle = 0,
		group = { { name = "Partick", realm = "Kneadmetal", class = "MAGE" } },
	})
	net:Add(me)
	net:Add(friend)
	return me, friend, net
end

-- "Add from group": the key the roster has for the other player.
local function addFromGroup(mock)
	local key = next(mock.ns.Roster.members)
	assert(key, "nobody in the roster")
	return assert(mock.ns.Friends:Add(key))
end

describe("Forever megaserver names (first name + surname)", function()
	after_each(H.checkClients)

	it("keys everyone as First-Surname", function()
		local me = megaPair()
		local Roster = me.ns.Roster
		assert.are.equal("Partick-Kneadmetal", Roster:GetPlayerName())
		assert.is_not_nil(Roster.members["Headdleonty-Kneadmetal"])
		assert.are.equal("Headdleonty-Kneadmetal", Roster:Normalize("Headdleonty Kneadmetal"))
		assert.are.equal("Headdleonty-Kneadmetal", Roster:Normalize("Headdleonty Kneadmetal-ClassicBetaPvE2"))
		assert.are.equal("Max-Classic Beta PvE", Roster:Normalize("Max-Classic Beta PvE")) -- a realm with spaces stays
		assert.is_true(Roster:IsPlayer("Partick Kneadmetal"))
		assert.is_true(Roster:IsPlayer("Partick"))
		assert.is_false(Roster:IsPlayer("Headdleonty"))
		assert.are.equal("Headdleonty-Kneadmetal", me.ns.Friends:ParseName("headdleonty kneadmetal"))
		assert.are.equal("Headdleonty-Kneadmetal", me.ns.Friends:ParseName("Headdleonty-Kneadmetal"))
	end)

	it("connects two friends who added each other from the group", function()
		local me, friend, net = megaPair()
		addFromGroup(me)
		addFromGroup(friend)
		net:Advance(8)
		assert.is_true(me.ns.Friends:IsConfirmed("Headdleonty-Kneadmetal"))
		assert.is_true(friend.ns.Friends:IsConfirmed("Partick-Kneadmetal"))
		assert.is_false(me:ChatContains("not on your LooserPiml friends list"))
		-- ticker: the friend dies, I get the banner with his first name
		friend.player.dead = true
		friend:Fire("PLAYER_DEAD")
		net:Advance(1)
		assert.are.equal("Headdleonty died.", H.lastRendered(me))
	end)

	it("connects with different surnames and when added by typed 'First Surname'", function()
		local me, friend, net = megaPair("Ironbrew")
		assert(me.ns.Friends:Add("Headdleonty Ironbrew"))
		assert(friend.ns.Friends:Add("partick kneadmetal"))
		net:Advance(8)
		assert.is_true(me.ns.Friends:IsConfirmed("Headdleonty-Ironbrew"))
		assert.is_true(friend.ns.Friends:IsConfirmed("Partick-Kneadmetal"))
	end)

	for _, form in ipairs({ { "Partick Kneadmetal", "Headdleonty Kneadmetal" }, { "Partick", "Headdleonty" } }) do
		it("plays a ranked duel when the game names players as '" .. form[1] .. "'", function()
			local me, friend, net = megaPair()
			addFromGroup(me)
			addFromGroup(friend)
			net:Advance(8)
			me:ChallengeToDuel("party1") -- unit menu
			friend:DuelRequested(form[1])
			net:Advance(1)
			assert.is_true(stats(me).DuelPanel:IsShown())
			assert.is_true(stats(friend).DuelPanel:IsShown())
			stats(me).DuelPanel.frame.ranked:Click()
			stats(friend).DuelPanel.frame.ranked:Click()
			friend:AcceptDuelRequest()
			net:Advance(5)
			local text = form[1] .. " has defeated " .. form[2] .. " in a duel"
			me:DuelEnded(text)
			friend:DuelEnded(text)
			net:Advance(1)
			assert.are.equal(1, stats(me).Duels:GetRecord("Headdleonty-Kneadmetal").rw)
			assert.are.equal(1, stats(friend).Duels:GetRecord("Partick-Kneadmetal").rl)
			assert.is_truthy(H.lastRendered(friend):find("Partick won a ranked duel against Headdleonty", 1, true))
		end)
	end
end)
