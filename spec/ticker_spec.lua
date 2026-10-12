local H = require("helpers")

local function lastTick(mock)
	local ns = mock.ns
	for i = #mock.sent, 1, -1 do
		local envelope = ns.Comm:Decode(mock.sent[i].text)
		if envelope and envelope.t == "TICK" then
			return envelope.d, envelope
		end
	end
	return nil
end

describe("Ticker", function()
	after_each(H.checkClients)

	describe("own events", function()
		it("death: shows locally, counts and broadcasts", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			mock.player.dead = true
			mock:Fire("PLAYER_DEAD")
			mock:Advance(1)
			assert.are.equal("Me died.", H.lastRendered(mock))
			assert.is_true(mock:ChatContains("Me|r died."))
			assert.are.equal(1, ns:GetModule("Ticker").Stats:GetSessionDeaths("Me-TestRealm"))
			local tick = lastTick(mock)
			assert.are.equal("death", tick.k)
			assert.are.equal("HUNTER", tick.c)
			assert.are.equal("Elwynn Forest", tick.z)
			assert.is_nil(tick.dr)
			H.assertNoErrors(mock)
		end)

		it("counts one death per death, not per duplicate event", function()
			local mock, ns = H.client()
			mock.player.dead = true
			mock:Fire("PLAYER_DEAD")
			mock:Fire("PLAYER_DEAD")
			mock:Fire("PLAYER_ALIVE") -- released: still a ghost
			mock:Fire("PLAYER_DEAD")
			local stats = ns:GetModule("Ticker").Stats
			assert.are.equal(1, stats:GetSessionDeaths("Me-TestRealm"))
			mock.player.dead = false
			mock:Fire("PLAYER_UNGHOST")
			mock.player.dead = true
			mock:Fire("PLAYER_DEAD")
			assert.are.equal(2, stats:GetSessionDeaths("Me-TestRealm"))
		end)

		it("second death of the session uses an 'again' variant with the count", function()
			local mock = H.client()
			mock:Fire("PLAYER_DEAD")
			mock:Fire("PLAYER_UNGHOST")
			mock:Fire("PLAYER_DEAD")
			mock:Advance(15)
			assert.are.equal("Me died. Again. (2 today)", H.lastRendered(mock))
		end)

		it("level up broadcasts the new level", function()
			local mock = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			mock:Fire("PLAYER_LEVEL_UP", 11, 20, 15, 1, 0, 1, 1, 1, 1)
			mock:Advance(1)
			assert.are.equal("Me reached level 11!", H.lastRendered(mock))
			assert.are.equal(11, lastTick(mock).lvl)
		end)

		it("works solo: local display, nothing sent", function()
			local mock = H.client()
			mock:Fire("PLAYER_LEVEL_UP", 11)
			mock:Advance(1)
			assert.are.equal(1, #mock.rendered)
			assert.are.equal(0, #mock.sent)
		end)
	end)

	describe("drowning", function()
		local mock

		before_each(function()
			mock = H.client()
		end)

		it("detects a death while the breath timer ran out", function()
			mock:Fire("MIRROR_TIMER_START", "BREATH", 3000, 180000, -1, 0, "Breath")
			mock:Advance(5) -- breath is gone, drowning damage ticks
			mock:Fire("PLAYER_DEAD")
			assert.are.equal("Me drowned. Water 1, Me 0.", H.lastRendered(mock))
		end)

		it("also works when MIRROR_TIMER_STOP arrives just before PLAYER_DEAD", function()
			mock:Fire("MIRROR_TIMER_START", "BREATH", 1000, 180000, -1, 0, "Breath")
			mock:Advance(2)
			mock:Fire("MIRROR_TIMER_STOP", "BREATH")
			mock:Fire("PLAYER_DEAD")
			assert.matches("drowned", H.lastRendered(mock))
		end)

		it("prefers GetMirrorTimerProgress when it reports breath left", function()
			mock:Fire("MIRROR_TIMER_START", "BREATH", 3000, 180000, -1, 0, "Breath")
			mock:Advance(5)
			mock.mirror.BREATH = 60000 -- client says plenty of breath left
			mock:Fire("PLAYER_DEAD")
			assert.are.equal("Me died.", H.lastRendered(mock))
		end)

		it("is a normal death with plenty of breath left", function()
			mock:Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
			mock:Advance(10)
			mock:Fire("PLAYER_DEAD")
			assert.are.equal("Me died.", H.lastRendered(mock))
		end)

		it("is a normal death while breath refills or long after surfacing", function()
			mock:Fire("MIRROR_TIMER_START", "BREATH", 0, 180000, 10, 0, "Breath")
			mock:Fire("PLAYER_DEAD")
			assert.are.equal("Me died.", H.lastRendered(mock))
			mock:Fire("PLAYER_UNGHOST")
			mock:Advance(15)
			mock:Fire("MIRROR_TIMER_START", "BREATH", 500, 180000, -1, 0, "Breath")
			mock:Advance(1)
			mock:Fire("MIRROR_TIMER_STOP", "BREATH")
			mock:Advance(10)
			mock:Fire("PLAYER_DEAD")
			assert.matches("Again", H.lastRendered(mock))
		end)

		it("ignores other mirror timers", function()
			mock:Fire("MIRROR_TIMER_START", "EXHAUSTION", 0, 60000, -1, 0, "Fatigue")
			mock:Advance(2)
			mock:Fire("PLAYER_DEAD")
			assert.are.equal("Me died.", H.lastRendered(mock))
		end)

		it("drops the drowned variant when timer values are secret", function()
			local secret = H.Mock.Secret()
			mock:Fire("MIRROR_TIMER_START", "BREATH", secret, secret, secret, 0, "Breath")
			mock:Advance(5)
			mock:Fire("PLAYER_DEAD")
			assert.are.equal("Me died.", H.lastRendered(mock))
			H.assertNoErrors(mock)
		end)
	end)

	describe("dungeons", function()
		it("announces entering and leaving, but not the login/reload baseline", function()
			local mock = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			mock.instance = { inInstance = true, type = "party", name = "The Deadmines", id = 36 }
			mock:Fire("PLAYER_ENTERING_WORLD", false, true) -- /reload inside
			assert.are.equal(0, #mock.rendered)

			mock:LeaveInstance()
			mock:Advance(3) -- waits COMBINE_DELAY for friends leaving too
			assert.are.equal("Me left The Deadmines.", H.lastRendered(mock))
			mock:Advance(20 * 60)
			mock:EnterInstance("Wailing Caverns", "party", 43)
			mock:Advance(10)
			assert.are.equal("Me entered Wailing Caverns.", H.lastRendered(mock))
			local tick = lastTick(mock)
			assert.are.equal("enter", tick.k)
			assert.are.equal("Wailing Caverns", tick.i)
			assert.are.equal("party", tick.it)
		end)

		it("stays quiet on a corpse run (release, run back in)", function()
			local mock = H.client()
			mock:EnterInstance("The Deadmines", "party", 36)
			mock:Advance(10)
			local shown = #mock.rendered
			mock.player.dead = true
			mock:Fire("PLAYER_DEAD")
			mock:Advance(10)
			shown = #mock.rendered
			mock:LeaveInstance() -- released, ghost at the graveyard
			mock.player.dead = false
			mock:Fire("PLAYER_UNGHOST")
			mock:EnterInstance("The Deadmines", "party", 36)
			mock:Advance(10)
			assert.are.equal(shown, #mock.rendered)
		end)

		it("ignores battlegrounds and the open world", function()
			local mock = H.client()
			mock:EnterInstance("Warsong Gulch", "pvp", 489)
			mock:LeaveInstance()
			mock:Advance(10)
			assert.are.equal(0, #mock.rendered)
		end)
	end)

	describe("receiving", function()
		it("shows a friend's death with their class color and counts it", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, friends = { "Max" } })
			local text = ns.Comm:Encode({ v = 1, t = "TICK", s = 1, id = 1, d = { k = "death", c = "WARRIOR" } })
			mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Max-TestRealm")
			mock:Advance(1)
			assert.matches("|cffc69b6dMax|r died.", mock.rendered[#mock.rendered], 1, true)
			assert.are.equal(1, ns:GetModule("Ticker").Stats:Get("Max-TestRealm", "alltime").deaths)
		end)

		it("neutralizes escape sequences and drops malformed events", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, friends = { "Max" } })
			local evil = ns.Comm:Encode({ v = 1, t = "TICK", s = 1, id = 1, d = {
				k = "enter", i = "|Hitem:1|h[Free Gold]|h|TInterface\\x:999|t", c = "|cff000000",
			} })
			mock:Fire("CHAT_MSG_ADDON", "LPiml", evil, "WHISPER", "Max-TestRealm")
			mock:Advance(3)
			local shown = mock.rendered[#mock.rendered]
			assert.is_truthy(shown:find("||Hitem:1||h[Free Gold]||h||TInterface", 1, true))
			-- with escaped pipes removed, no link or foreign texture is left
			local undoubled = shown:gsub("||", "")
			assert.is_nil(undoubled:find("|H", 1, true))
			assert.is_nil(undoubled:find("|TInterface\\x", 1, true))
			assert.is_truthy(shown:find("Max", 1, true))

			local before = #mock.rendered
			for i, data in ipairs({ { k = "explode" }, "string", { lvl = 5 } }) do
				local text = ns.Comm:Encode({ v = 1, t = "TICK", s = 1, id = 10 + i, d = data })
				mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Max-TestRealm")
			end
			mock:Advance(20)
			assert.are.equal(before, #mock.rendered)
			H.assertNoErrors(mock)
		end)
	end)

	describe("encounters", function()
		it("holds banners during a boss and shows them afterwards", function()
			local clients = H.group({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			me:StartEncounter()
			max:StartEncounter()

			max.player.dead = true
			max:Fire("PLAYER_DEAD") -- Max dies mid-fight
			me:Advance(5)
			assert.are.equal(0, #me.rendered)
			assert.are.equal(0, #max.rendered) -- own banner held too

			me:EndEncounter()
			max:EndEncounter()
			me:Advance(3)
			assert.are.equal("During the boss: Max died.", H.lastRendered(me))
			assert.are.equal("During the boss: Max died.", H.lastRendered(max))
			assert.is_true(me:ChatContains("During the boss:"))
			H.assertNoErrors(me)
			H.assertNoErrors(max)
		end)

		it("releases held banners even if no encounter-end event arrives", function()
			local mock, ns = H.client({ testMode = true })
			mock.encounter = true -- only the client API says so, no ENCOUNTER_START/END
			ns.Slash:Dispatch("sim death Max")
			mock:Advance(5)
			assert.are.equal(0, #mock.rendered)
			mock.encounter = false
			mock:Advance(3)
			assert.are.equal("[test] During the boss: Max died.", H.lastRendered(mock))
		end)

		it("collapses many held events into a few banners plus a summary", function()
			local mock, ns = H.client({ testMode = true })
			ns.Events:SetSimulatedEncounter(true, "Boss")
			for _ = 1, 8 do
				ns.Slash:Dispatch("sim death Max")
			end
			ns.Events:SetSimulatedEncounter(false)
			mock:Advance(60)
			local plain = H.renderedPlain(mock)
			assert.are.equal(6, #plain)
			assert.are.equal("... and 3 more (see chat)", plain[6])
		end)
	end)

	describe("test mode pipeline", function()
		it("/lp sim death Max: loopback -> receive -> stats -> display, nothing sent", function()
			local mock, ns = H.client({ testMode = true, group = { { name = "Real", class = "PRIEST" } } })
			local before = #mock.sent
			mock.env.SlashCmdList.LOOSERPIML("sim death Max")
			mock:Advance(1)
			assert.are.equal("[test] Max died.", H.lastRendered(mock))
			assert.is_truthy(mock.rendered[#mock.rendered]:find("|cffc69b6dMax|r", 1, true)) -- fake Max is a warrior
			local stats = ns:GetModule("Ticker").Stats
			assert.are.equal(1, stats:GetSessionDeaths("Max-TestRealm"))
			assert.is_nil(stats:Get("Max-TestRealm", "alltime"))
			assert.are.equal(before, #mock.sent)
			H.assertNoErrors(mock)
		end)

		it("simulates own events and every kind", function()
			local mock = H.client({ testMode = true })
			for _, cmd in ipairs({ "sim death", "sim drown Lena", "sim levelup", "sim ding Jo", "sim enter Kim", "sim leave" }) do
				mock.ns.Slash:Dispatch(cmd)
			end
			mock:Advance(60)
			local plain = H.renderedPlain(mock)
			assert.are.equal(6, #plain)
			assert.matches("Me died", plain[1])
			assert.matches("Lena drowned", plain[2])
			assert.matches("Me reached level 11", plain[3])
			assert.matches("Jo reached level", plain[4])
			assert.matches("Kim entered The Deadmines", plain[5])
			assert.matches("Me left The Deadmines", plain[6])
			H.assertNoErrors(mock)
		end)

		it("/lp sim boss holds events and releases them after the fake encounter", function()
			local mock = H.client({ testMode = true })
			mock.ns.Slash:Dispatch("sim boss")
			mock:Advance(5)
			assert.are.equal(0, #mock.rendered)
			mock:Advance(10)
			mock:Advance(20)
			local plain = H.renderedPlain(mock)
			assert.are.equal(2, #plain)
			assert.are.equal("[test] During the boss: Max died.", plain[1])
			assert.matches("Me died", plain[2])
			assert.is_true(mock:ChatContains("Simulated boss encounter ended"))
		end)

		it("refuses to simulate outside test mode", function()
			local mock = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			mock.ns.Slash:Dispatch("sim death Max")
			mock:Advance(1)
			assert.are.equal(0, #mock.rendered)
			assert.is_true(mock:ChatContains("only run in test mode"))
		end)
	end)

	describe("banner sound", function()
		it("plays a sound per event kind when the banner appears, on the Master channel", function()
			local mock = H.client({ testMode = true })
			mock.ns.Slash:Dispatch("sim death Max")
			mock:Advance(10)
			mock.ns.Slash:Dispatch("sim levelup Jo")
			mock:Advance(10)
			mock.ns.Slash:Dispatch("sim enter Kim") -- silent
			mock:Advance(10)
			assert.are.equal(2, #mock.sounds)
			assert.are.equal(8959, mock.sounds[1].id)
			assert.are.equal(888, mock.sounds[2].id)
			assert.are.equal("Master", mock.sounds[1].channel)
		end)

		it("can be turned off with /lp sound off and the choice persists", function()
			local mock, ns = H.client({ testMode = true })
			ns.Slash:Dispatch("sound off")
			assert.is_true(mock:ChatContains("Banner sound: off"))
			ns.Slash:Dispatch("sim death Max")
			mock:Advance(10)
			assert.are.equal(0, #mock.sounds)
			assert.is_false(mock.env.LooserPimlDB.modules.Ticker.banner.sound)
			ns.Slash:Dispatch("sound on")
			assert.is_true(mock:ChatContains("Banner sound: on"))
		end)

		it("does not play while a boss fight holds the banner, but when it is shown", function()
			local mock, ns = H.client({ testMode = true })
			ns.Events:SetSimulatedEncounter(true, "Boss")
			ns.Slash:Dispatch("sim death Max")
			mock:Advance(3)
			assert.are.equal(0, #mock.sounds)
			ns.Events:SetSimulatedEncounter(false)
			mock:Advance(3)
			assert.are.equal(1, #mock.sounds)
		end)
	end)

	describe("friends' events", function()
		local function friendDeath(ns, id)
			ns.Comm:SimulateReceive("Max", "TICK", { k = "death", c = "WARRIOR" })
		end

		it("'Ticker messages from friends': Banner (default), Chat line only, Off", function()
			local mock, ns = H.client({ testMode = true })
			assert.are.equal("banner", ns.Options:Get("ticker.friends"))
			friendDeath(ns)
			mock:Advance(6)
			assert.are.equal(1, #mock.rendered)
			assert.are.equal(1, #mock.sounds)

			ns.Options:Set("ticker.friends", "chat")
			local lines = #mock.chat
			friendDeath(ns)
			mock:Advance(6)
			assert.are.equal(1, #mock.rendered) -- no new banner
			assert.are.equal(1, #mock.sounds)   -- and no sound
			assert.are.equal(lines + 1, #mock.chat)
			assert.is_true(mock.chat[#mock.chat]:find("Max", 1, true) ~= nil)

			ns.Options:Set("ticker.friends", "off")
			lines = #mock.chat
			friendDeath(ns)
			mock:Advance(6)
			assert.are.equal(1, #mock.rendered)
			assert.are.equal(lines, #mock.chat)
			assert.are.equal(3, ns:GetModule("Ticker").Stats:GetSessionDeaths("Max-TestRealm")) -- counted every time

			ns.Slash:Dispatch("sim death") -- own events are not affected
			mock:Advance(6)
			assert.are.equal(2, #mock.rendered)
			ns.Options:Set("ticker.friends", "nonsense") -- only the offered values are taken
			assert.are.equal("off", ns.Options:Get("ticker.friends"))
		end)

		it("chat-line-only events during a boss come out as chat lines afterwards, never as banners", function()
			local mock, ns = H.client({ testMode = true })
			ns.Options:Set("ticker.friends", "chat")
			ns.Events:SetSimulatedEncounter(true, "Boss")
			friendDeath(ns)
			mock:Advance(3)
			assert.is_false(mock:ChatContains("Max|r died"))
			ns.Events:SetSimulatedEncounter(false)
			mock:Advance(5)
			assert.is_true(mock:ChatContains("During the boss:"))
			assert.are.equal(0, #mock.rendered)
		end)

		it("friends entering the same dungeon together get one banner with all names", function()
			local clients = H.friends({
				{ name = "Me", class = "HUNTER" },
				{ name = "Max", class = "WARRIOR" },
				{ name = "Lootius", class = "MAGE" },
			})
			local me, max, lootius = clients[1], clients[2], clients[3]
			me:Advance(40) -- login traffic (handshakes, stats) is through ChatThrottleLib
			me.rendered = {}
			max:EnterInstance("The Deadmines", "party", 36)
			me:Advance(0.5) -- Max is a moment faster
			lootius:EnterInstance("The Deadmines", "party", 36)
			me:Advance(10)
			local plain = H.renderedPlain(me)
			assert.are.equal(1, #plain)
			assert.are.equal("Max and Lootius entered The Deadmines.", plain[1])
			assert.is_true(me:ChatContains("|cffc69b6dMax|r and |cff3fc7ebLootius|r entered The Deadmines."))
		end)
	end)

	describe("two clients end to end", function()
		it("my death appears on my friend's screen and in their stats", function()
			local clients = H.group({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			me.player.dead = true
			me:Fire("PLAYER_DEAD")
			me:Advance(2)
			assert.are.equal("Me died.", H.lastRendered(me))
			assert.are.equal("Me died.", H.lastRendered(max))
			assert.is_truthy(max.rendered[#max.rendered]:find("|cffaad372Me|r", 1, true)) -- hunter green
			assert.are.equal(1, max.ns:GetModule("Ticker").Stats:Get("Me-TestRealm", "alltime").deaths)
			assert.are.equal(1, #me.rendered) -- the echo of my own message is not shown twice
			H.assertNoErrors(me)
			H.assertNoErrors(max)
		end)
	end)
end)
