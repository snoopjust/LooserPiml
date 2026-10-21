local H = require("helpers")

-- Decoded LooserPiml messages a client handed to the network, with how.
local function sentMessages(mock)
	return H.decodedSent(mock)
end

-- Messages `to` received that came from `from`.
local function receivedFrom(to, from)
	local n = 0
	for _, msg in ipairs(to.received) do
		if msg.from == from then
			n = n + 1
		end
	end
	return n
end

local function types(messages)
	local seen = {}
	for _, m in ipairs(messages) do
		seen[m.t] = (seen[m.t] or 0) + 1
	end
	return seen
end

local function die(mock)
	mock.player.dead = true
	mock:Fire("PLAYER_DEAD")
	mock.player.dead = false
	mock:Fire("PLAYER_UNGHOST")
end

-- A valid message as `sender` would send it.
local function incoming(mock, msgType, data, id)
	return mock.ns.Comm:Encode({ v = 1, t = msgType, s = 77, id = id or 1, d = data })
end

describe("LooserPiml friends", function()
	after_each(H.checkClients)

	describe("the list", function()
		it("turns typed names into Name-Realm and rejects anything else", function()
			local _, ns = H.client()
			local F = ns.Friends
			assert.are.equal("Max-TestRealm", F:ParseName("max"))
			assert.are.equal("Max-TestRealm", F:ParseName("  Max  "))
			assert.are.equal("Lena-OtherRealm", F:ParseName("lena-Other Realm"))
			assert.are.equal("Kim-AzjolNerub", F:ParseName("Kim-Azjol-Nerub"))
			for _, bad in ipairs({ "", "x", "Max1", "Max|cff", "|Hitem:1|h", "Ma x-", "a-b|c" }) do
				assert.is_nil(F:ParseName(bad), bad)
			end
			assert.is_nil(F:ParseName(H.Mock.Secret()))
		end)

		it("adds, refuses duplicates and yourself, removes, and keeps the list across a reload", function()
			local mock, ns = H.client()
			local F = ns.Friends
			assert.are.equal("Max-TestRealm", F:Add("Max"))
			local full, err = F:Add("max")
			assert.is_nil(full)
			assert.matches("already on your list", err)
			full, err = F:Add("Me")
			assert.is_nil(full)
			assert.matches("That is you", err)
			assert.is_nil((F:Add("1234")))
			F:Add("Lena-Other Realm")
			assert.are.equal(2, F:Count())
			assert.is_true(F:Remove("Max-TestRealm"))
			assert.is_false(F:Remove("Max-TestRealm"))
			local _, ns2 = H.client({ savedVariables = mock.env.LooserPimlDB })
			assert.is_true(ns2.Friends:IsListed("Lena-OtherRealm"))
			assert.is_false(ns2.Friends:IsListed("Max"))
		end)

		it("can be managed in the Friends tab: add by name, add from group, remove", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" }, { name = "Bob", class = "MAGE" } } })
			ns.TestMode:Enable() -- fake members must never be offered
			ns.Window:Open("friends")
			local frame = ns.Window.frame.tabFrames.friends
			assert.is_true(H.hasText(frame, "LooserPiml only talks to players on this list"))
			assert.is_true(H.hasText(frame, "Nobody yet"))

			frame.input:SetText("Lena")
			frame.addButton:Click()
			assert.is_true(ns.Friends:IsListed("Lena"))
			assert.is_true(H.hasText(frame, "Added Lena-TestRealm"))

			local offered = {}
			for _, button in ipairs(frame.fromGroup.buttons) do
				if button.shown and button.member then
					offered[#offered + 1] = button.member
				end
			end
			assert.are.same({ "Bob-TestRealm", "Max-TestRealm" }, offered) -- real members only, no fake Jo/Kim
			frame.fromGroup.buttons[2]:Click()
			assert.is_true(ns.Friends:IsListed("Max"))
			assert.is_true(H.hasText(frame, "Your list (2/40)"))
			assert.is_true(H.hasText(frame, "Max"))

			for _, row in ipairs(frame.rows) do
				if row.shown and row.friend == "Lena-TestRealm" then
					row.remove:Click()
				end
			end
			assert.is_false(ns.Friends:IsListed("Lena"))
			assert.is_true(H.hasText(frame, "Your list (1/40)"))
			ns.TestMode:Disable()
		end)

		it("never offers the own character, even if UnitName reports the realm oddly", function()
			local mock, ns = H.client()
			mock.G.UnitName = function(unit)
				if unit == "player" then
					return "Me", "Test Realm"
				end
			end
			ns.Roster:Scan()
			assert.are.same({}, ns.Friends:GetGroupCandidates())
			local db = ns.DB:Get("friends")
			db["Me-TestRealm"] = { added = 0 }
			ns.Friends:RemoveSelf()
			assert.is_nil(db["Me-TestRealm"])
		end)

		it("can add from the WoW friends list (online first) and explains why both lists matter", function()
			local mock, ns = H.client()
			mock.friendList.Zed = { connected = false, className = "Rogue" }
			mock.friendList.Lena = { connected = true, className = "Mage" }
			mock.friendList.Max = { connected = true, className = "Warrior" }
			ns.Friends:Add("Max")
			ns.Window:Open("friends")
			local frame = ns.Window.frame.tabFrames.friends
			assert.is_true(H.hasText(frame, "Add from WoW friends"))
			assert.is_true(H.hasText(frame, "group up to be sure"))
			local offered, labels = {}, {}
			for _, button in ipairs(frame.fromWoW.buttons) do
				if button.shown and button.member then
					offered[#offered + 1] = button.member
					labels[#labels + 1] = button.label.text_
				end
			end
			assert.are.same({ "Lena-TestRealm", "Zed-TestRealm" }, offered) -- Max is listed already; online first
			assert.is_truthy(labels[1]:find("|cff3fc7ebLena|r", 1, true)) -- class color from the localized class name
			assert.is_truthy(labels[2]:find("|cff999999Zed|r", 1, true)) -- offline: grey
			frame.fromWoW.buttons[1]:Click()
			assert.is_true(ns.Friends:IsListed("Lena"))
			assert.is_true(H.hasText(frame, "Nobody in your group") or H.hasText(frame, "Not in a group."))
		end)

		it("has its own settings page, reachable from the main settings page", function()
			local mock, ns = H.client()
			local sub = mock.settings.subcategories[1]
			assert.are.equal("LooserPiml friends", sub.name)
			local manage
			for _, init in ipairs(mock.settings.categories[1].layout.initializers) do
				if init.kind == "button" and init.name == "Friends list" then
					manage = init
				end
			end
			assert.is_table(manage)
			manage.onClick()
			assert.are.equal(4243, mock.settings.opened)
			sub.frame:Show()
			sub.frame.scripts.OnShow(sub.frame)
			assert.is_true(H.hasText(sub.frame, "Add by name"))
			assert.is_true(ns.Options:Open())
			assert.are.equal(4242, mock.settings.opened)
		end)

		it("/lp friends add|remove|list for power users", function()
			local mock, ns = H.client()
			ns.Slash:Dispatch("friends add Max")
			assert.is_true(ns.Friends:IsListed("Max"))
			ns.Slash:Dispatch("friends list")
			assert.is_true(mock:ChatContains("offline"))
			ns.Slash:Dispatch("friends remove max")
			assert.is_false(ns.Friends:IsListed("Max"))
			ns.Slash:Dispatch("friends")
			assert.are.equal("friends", ns.Window.selectedTab)
		end)

		it("tells you once after login (local chat) why nothing is shared while the list is empty", function()
			local function hints(mock)
				local n = 0
				for _, line in ipairs(mock.chat) do
					if line:find("friends list is empty", 1, true) then
						n = n + 1
					end
				end
				return n
			end
			local mock = H.client() -- solo
			assert.are.equal(1, hints(mock))
			mock:JoinGroup({ { name = "Max", class = "WARRIOR" } })
			mock:JoinGroup({ { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE" } })
			mock:Advance(10)
			assert.are.equal(1, hints(mock)) -- not again on joining a group
			assert.are.equal(0, #mock.sent)
			local withFriends = H.client({ friends = { "Max" } })
			assert.are.equal(0, hints(withFriends))
		end)
	end)

	describe("communication rule", function()
		it("a party/raid with a stranger: zero messages to the stranger, nothing on PARTY/RAID, friends get whispers", function()
			for _, raid in ipairs({ false, true }) do
				local clients = H.group({
					{ name = "Me", class = "HUNTER", friends = { "Max" } },
					{ name = "Max", class = "WARRIOR", friends = { "Me" } },
					-- runs LooserPiml and even lists Me: still gets nothing from Me
					{ name = "Stranger", class = "ROGUE", friends = { "Me" } },
				})
				local me, max, stranger = clients[1], clients[2], clients[3]
				if raid then
					for _, c in ipairs(clients) do
						c:JoinGroup(c.group, true)
					end
				end
				die(me) -- ticker + stats
				me:Advance(40)
				me:StartEncounter() -- held during the boss, flushed afterwards
				die(me)
				me:Advance(5)
				me:EndEncounter()
				me:Advance(40)
				local mine = sentMessages(me)
				assert.is_true(#mine > 0)
				for _, m in ipairs(mine) do
					assert.are.equal("WHISPER", m.chatType, tostring(m.t) .. " went to " .. tostring(m.chatType))
					assert.are.equal("Max", m.target)
				end
				local sentTypes = types(mine)
				assert.is_true((sentTypes.TICK or 0) >= 2)
				assert.is_true((sentTypes.STATS or 0) >= 1)
				assert.is_true((sentTypes.HELLO or 0) >= 1)
				assert.are.equal(0, receivedFrom(stranger, me))
				assert.is_true(receivedFrom(max, me) > 0)
				assert.is_true(H.lastRendered(max):find("Me died", 1, true) ~= nil)
				-- what Stranger sent to Me was dropped unread
				assert.is_nil(me.ns.Version.known["Stranger-TestRealm"])
				assert.is_false(me.ns.Friends:IsListed("Stranger"))
				H.assertRecipientsOk(me)
			end
		end)

		it("sends nothing to a non-listed player in any code path", function()
			local clients = H.group({
				{ name = "Me", class = "HUNTER", friends = {} },
				{ name = "Stranger", class = "ROGUE", friends = { "Me" } },
			})
			local me, stranger = clients[1], clients[2]
			local ns = me.ns
			die(me)                                         -- ticker + stats
			me:Fire("PLAYER_LEVEL_UP", 11)
			me:EnterInstance("The Deadmines", "party", 36)  -- ticker
			me:Advance(40)
			me:StartEncounter()                             -- encounter queue
			die(me)
			me:EndEncounter()
			me:Advance(10)
			me:JoinGroup({ { name = "Stranger", class = "ROGUE" }, { name = "Bob", class = "MAGE" } }) -- version check on join
			me:Fire("FRIENDLIST_UPDATE")
			ns.Slash:Dispatch("selftest")                    -- real transport test
			me:Advance(40)
			assert.is_true(me:ChatContains("no LooserPiml friend is connected right now"))
			assert.are.same({}, sentMessages(me))
			assert.are.equal(0, receivedFrom(stranger, me))
			assert.are.equal(0, #ns.Comm.queue)
		end)

		it("drops every message from senders who are not on the list", function()
			local mock, ns = H.client({ group = { { name = "Stranger", class = "ROGUE" } } })
			local before = #mock.sent
			local data = {
				HELLO = { ver = "v9.9.9", proto = 1 },
				TICK = { k = "death", c = "ROGUE" },
				STATS = { mv = 1, day = "x", week = "y", class = "ROGUE", p = { all = { n = { deaths = 9 } } } },
			}
			local id = 0
			for _, channel in ipairs({ "PARTY", "WHISPER" }) do
				for msgType, payload in pairs(data) do
					id = id + 1
					mock:Fire("CHAT_MSG_ADDON", "LPiml", incoming(mock, msgType, payload, id), channel, "Stranger-TestRealm")
				end
			end
			mock:Advance(10)
			assert.are.equal(0, #mock.rendered)
			assert.is_nil(ns.Version.known["Stranger-TestRealm"])
			assert.are.same({}, ns:GetModule("Stats").db.friendStats)
			assert.is_nil(ns:GetModule("Ticker").Stats:Get("Stranger-TestRealm", "alltime"))
			assert.are.equal(1, #ns:GetModule("Stats"):GetParticipants("all")) -- only me
			assert.are.equal(before, #mock.sent) -- no answer either
			assert.is_false(mock:ChatContains("newer LooserPiml"))
		end)

		it("removing a friend stops all traffic to them at once, held messages included", function()
			local clients = H.group({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			me:Advance(40)
			assert.is_true(me.ns.Friends:IsConfirmed("Max"))
			me:StartEncounter()
			die(me) -- TICK and STATS are now held
			me:Advance(5)
			assert.is_true(#me.ns.Comm.queue > 0)

			me.ns.Window:Open("friends") -- remove with the button, like a player would
			local frame = me.ns.Window.frame.tabFrames.friends
			for _, row in ipairs(frame.rows) do
				if row.shown and row.friend == "Max-TestRealm" then
					row.remove:Click()
				end
			end
			assert.is_false(me.ns.Friends:IsListed("Max"))
			local before = #me.sent
			local maxGot = receivedFrom(max, me)
			me:EndEncounter()
			die(me)
			me:Fire("PLAYER_LEVEL_UP", 12)
			me:Advance(60)
			assert.are.equal(before, #me.sent)
			assert.are.equal(maxGot, receivedFrom(max, me))
			-- and whatever Max still sends is dropped
			local shown = #me.rendered
			die(max)
			me:Advance(5)
			assert.is_true(receivedFrom(me, max) > 0)
			assert.are.equal(shown, #me.rendered)
		end)

		it("a one-sided friend gets only the handshake until they add you too", function()
			local clients = H.group({
				{ name = "Me", class = "HUNTER", friends = { "Max" } },
				{ name = "Max", class = "WARRIOR", friends = {} },
			})
			local me, max = clients[1], clients[2]
			die(me)
			me:Advance(40)
			assert.are.same({ HELLO = 1 }, types(sentMessages(me)))
			assert.is_false(me.ns.Friends:IsConfirmed("Max"))
			assert.are.equal(1, #me.ns:GetModule("Stats"):GetParticipants("all")) -- not on the leaderboard
			assert.are.equal(0, me.ns:GetModule("Stats"):CountOnlineFriends())
			assert.are.equal(0, #max.rendered)

			max.ns.Friends:Add("Me") -- now it is mutual
			max:Advance(2)
			assert.is_true(me.ns.Friends:IsConfirmed("Max"))
			assert.is_true(max.ns.Friends:IsConfirmed("Me"))
			die(me)
			me:Advance(2)
			assert.matches("Me died", H.lastRendered(max))
			assert.are.equal(1, me.ns:GetModule("Stats"):CountOnlineFriends())
		end)

		it("whispers friends who are online on the friends list, never offline ones", function()
			local net = H.Mock.NewNetwork()
			local me = H.client({ name = "Me", friends = { "Lena", "Kim" }, settle = 0 })
			local lena = H.client({ name = "Lena", class = "MAGE", friends = { "Me" }, settle = 0 })
			net:Add(me)
			net:Add(lena)
			me.friendList.Lena = { connected = true, name = "Lena" }
			me.friendList.Kim = { connected = false, name = "Kim" }
			net:Advance(8) -- login handshake; Lena answers although Me isn't on her friends list
			assert.is_true(me.ns.Friends:IsConfirmed("Lena"))
			assert.is_true(lena.ns.Friends:IsConfirmed("Me"))
			die(me)
			net:Advance(40)
			for _, m in ipairs(sentMessages(me)) do
				assert.are.equal("Lena", m.target)
			end
			assert.is_true((types(sentMessages(me)).STATS or 0) >= 1) -- not grouped: stats ...
			assert.is_true((types(sentMessages(me)).TICK or 0) >= 1)  -- ... and ticker events
			assert.matches("Me died", H.lastRendered(lena))

			-- Lena logs off: her handshake is forgotten, nothing more goes to her
			me.friendList.Lena.connected = false
			lena.online = false
			me:Fire("FRIENDLIST_UPDATE")
			assert.is_false(me.ns.Friends:IsConfirmed("Lena"))
			local before = #me.sent
			die(me)
			net:Advance(40)
			assert.are.equal(before, #me.sent)
			-- she comes back: a fresh handshake first
			me.friendList.Lena.connected = true
			lena.online = true
			me:Fire("FRIENDLIST_UPDATE")
			net:Advance(2)
			assert.is_true(me.ns.Friends:IsConfirmed("Lena"))
		end)

		it("two connected friends who are NOT grouped exchange stats and ticker events", function()
			local clients = H.friends({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			assert.are.equal(0, #me.group)
			assert.is_true(me.ns.Friends:IsConnected("Max"))
			assert.is_true(max.ns.Friends:IsConnected("Me"))
			die(max)
			max:Fire("PLAYER_LEVEL_UP", 11)
			me:Advance(40)
			local plain = H.renderedPlain(me)
			assert.are.equal("Max died.", plain[1])
			assert.are.equal("Max reached level 11!", plain[2])
			local stats = me.ns:GetModule("Stats")
			local maxEntry
			for _, p in ipairs(stats:GetParticipants("tonight")) do
				if p.name == "Max-TestRealm" then
					maxEntry = p
				end
			end
			assert.is_table(maxEntry)
			assert.is_true(maxEntry.online)
			assert.are.equal(1, stats.Model.Get(maxEntry.agg, "deaths"))
			assert.are.equal(1, stats:CountOnlineFriends())
			for _, c in ipairs(clients) do
				for _, call in ipairs(c.sent) do
					assert.are.equal("WHISPER", call.chatType)
				end
			end
		end)

		it("does not whisper group members who are offline", function()
			local mock = H.client({
				group = { { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE", offline = true }, { name = "Bob", class = "ROGUE" } },
				confirmed = { "Max", "Lena" },
			})
			die(mock)
			mock:Advance(40)
			for _, m in ipairs(sentMessages(mock)) do
				assert.are.equal("Max", m.target)
			end
		end)

		it("test mode never sends anything to real players, even messages held until after it ends", function()
			local clients = H.group({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			me:Advance(40)
			local ns = me.ns
			ns.TestMode:Enable()
			local before = #me.sent
			ns.Slash:Dispatch("sim death Max")
			ns.Slash:Dispatch("sim levelup")
			ns:GetModule("Stats"):FillSampleFriends()
			die(me) -- a real event while in test mode: loops back only
			ns.Slash:Dispatch("selftest")
			me:Advance(5)
			assert.is_true(me:ChatContains("not tested in test mode"))
			ns.Events:SetSimulatedEncounter(true, "Boss")
			ns.Slash:Dispatch("sim death") -- held
			assert.is_true(#ns.Comm.queue > 0)
			ns.TestMode:Disable()          -- held test messages are dropped, not sent
			me:Advance(40)
			for i = before + 1, #me.sent do
				local e = ns.Comm:Decode(me.sent[i].text)
				assert.is_not_nil(e)
				assert.are_not.equal("TICK", e.t, "a test-mode TICK went out")
			end
			assert.is_nil(me.env.LooserPimlDB.friends["Jo-TestRealm"]) -- sample friends stay out of the real list
			assert.are.equal(0, #max.rendered) -- Max saw nothing of Me's test session
		end)
	end)
end)
