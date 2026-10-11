local H = require("helpers")

local function ticks(mock)
	local n = 0
	for _, call in ipairs(mock.sent) do
		local e = mock.ns.Comm:Decode(call.text)
		if e and e.t == "TICK" then
			n = n + 1
		end
	end
	return n
end

describe("Options", function()
	after_each(H.checkClients)

	describe("defaults", function()
		it("registers every option with its default on a fresh install", function()
			local _, ns = H.client()
			local O = ns.Options
			for _, key in ipairs({ "ticker.levelup", "ticker.death", "ticker.drowned", "ticker.dungeon",
				"ticker.raid", "ticker.bossRecap", "ticker.own", "banner.sound", "stats.collect", "stats.share" }) do
				assert.is_true(O:Get(key), key)
			end
			assert.are.equal(4, O:Get("banner.hold"))
			assert.are.equal(40, O:Get("banner.size"))
			assert.is_false(O:Get("test.mode"))
			local titles = {}
			for _, section in ipairs(O.sections) do
				titles[#titles + 1] = section.id
			end
			assert.are.same({ "ticker", "banner", "stats", "testing" }, { titles[1], titles[2], titles[3], titles[#titles] })
		end)

		it("migrates v0.1.0 saved data: sound moves into the banner settings", function()
			local saved = { schemaVersion = 1, debug = false, modules = { Ticker = { sound = false, chatLog = true, stats = {} } } }
			local mock, ns = H.client({ savedVariables = saved })
			local db = mock.env.LooserPimlDB
			assert.are.equal(2, db.schemaVersion)
			assert.is_nil(db.modules.Ticker.sound)
			assert.is_false(db.modules.Ticker.banner.sound)
			assert.are.equal(4, db.modules.Ticker.banner.hold)
			assert.is_true(db.modules.Ticker.show.death)
			assert.is_false(ns.Options:Get("banner.sound"))
		end)
	end)

	describe("ticker message filters", function()
		it("hides a message type, but still counts and broadcasts it", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			ns.Options:Set("ticker.death", false)
			mock.player.dead = true
			mock:Fire("PLAYER_DEAD")
			mock:Advance(10)
			assert.are.equal(0, #mock.rendered)
			assert.are.equal(1, ticks(mock))
			assert.are.equal(1, ns:GetModule("Stats"):GetAggregates().tonight.n.deaths)
			ns.Options:Set("ticker.levelup", true)
			mock:Fire("PLAYER_LEVEL_UP", 11)
			mock:Advance(1)
			assert.are.equal(1, #mock.rendered)
		end)

		it("tells dungeons from raids and drownings from deaths", function()
			local mock, ns = H.client({ testMode = true })
			ns.Options:Set("ticker.raid", false)
			ns.Options:Set("ticker.drowned", false)
			ns.Slash:Dispatch("sim drown Max")
			ns:GetModule("Ticker"):Simulate("enter", "Lena") -- dungeon: shown
			ns.Comm:SimulateReceive("Jo", "TICK", { k = "enter", i = "Molten Core", it = "raid", c = "PRIEST" })
			mock:Advance(30)
			local plain = H.renderedPlain(mock)
			assert.are.equal(1, #plain)
			assert.matches("Lena entered", plain[1])
		end)

		it("'also show my own events' off: own events are not displayed, friends' still are", function()
			local mock, ns = H.client({ testMode = true })
			ns.Options:Set("ticker.own", false)
			ns.Slash:Dispatch("sim death")
			ns.Slash:Dispatch("sim death Max")
			mock:Advance(20)
			local plain = H.renderedPlain(mock)
			assert.are.equal(1, #plain)
			assert.matches("Max died", plain[1])
		end)

		it("boss recap off: held events go to chat only, no banners", function()
			local mock, ns = H.client({ testMode = true })
			ns.Options:Set("ticker.bossRecap", false)
			ns.Events:SetSimulatedEncounter(true, "Boss")
			ns.Slash:Dispatch("sim death Max")
			ns.Events:SetSimulatedEncounter(false)
			mock:Advance(20)
			assert.are.equal(0, #mock.rendered)
			assert.is_true(mock:ChatContains("During the boss:"))
		end)
	end)

	describe("banner settings", function()
		it("applies display time and size", function()
			local mock, ns = H.client({ testMode = true })
			ns.Options:Set("banner.hold", 8)
			ns.Options:Set("banner.size", 56)
			ns.Options:Set("banner.size", 500) -- clamped to the slider range
			ns.Slash:Dispatch("sim death Max")
			ns.Slash:Dispatch("sim death Lena")
			mock:Advance(6)
			assert.are.equal(1, #mock.rendered) -- still showing the first after 6 s
			mock:Advance(4)
			assert.are.equal(2, #mock.rendered)
			local frame = ns:GetModule("Ticker").Display.frame
			assert.are.equal(64, frame.text.fontSize)
			assert.are.equal(8, frame.holdAnim.duration)
		end)

		it("moves, saves and resets the banner position", function()
			local mock, ns = H.client()
			local Display = ns:GetModule("Ticker").Display
			Display:ToggleUnlocked()
			local frame = Display.frame
			assert.is_true(frame.mouseEnabled)
			assert.is_true(mock:ChatContains("Banner unlocked"))
			frame:ClearAllPoints()
			frame:SetPoint("TOP", mock.env.UIParent, "TOP", 0, -120)
			frame.scripts.OnDragStop(frame)
			assert.are.same({ "TOP", "TOP", 0, -120 }, mock.env.LooserPimlDB.modules.Ticker.banner.point)
			Display:ToggleUnlocked()
			assert.is_false(frame.mouseEnabled) -- click-through again
			Display:ResetPosition()
			assert.is_nil(mock.env.LooserPimlDB.modules.Ticker.banner.point)
			assert.are.equal("CENTER", frame:GetPoint(1))
		end)
	end)

	describe("Blizzard settings panel", function()
		it("builds one category with sections, checkboxes, sliders and buttons bound to live values", function()
			local mock, ns = H.client()
			local category = mock.settings.registered
			assert.is_table(category)
			assert.are.equal("LooserPiml", category.name)
			local kinds = {}
			for _, init in ipairs(category.layout.initializers) do
				kinds[init.kind] = (kinds[init.kind] or 0) + 1
			end
			assert.is_true(kinds.header >= 4)
			assert.is_true(kinds.checkbox >= 10)
			assert.are.equal(2, kinds.slider)
			assert.is_true(kinds.button >= 7)

			local setting = mock.settings.byVariable.LooserPiml_ticker_death
			assert.is_true(setting:GetValue())
			setting:SetValue(false)
			assert.is_false(mock.env.LooserPimlDB.modules.Ticker.show.death)
			ns.Slash:Dispatch("sound off")
			assert.is_false(mock.settings.byVariable.LooserPiml_banner_sound:GetValue()) -- live, not cached

			ns.Slash:Dispatch("options")
			assert.are.equal(4242, mock.settings.opened)
		end)

		it("asks for confirmation before resetting my stats", function()
			local mock, ns = H.client()
			mock:Fire("PLAYER_DEAD")
			local stats = ns:GetModule("Stats")
			assert.are.equal(1, stats:GetAggregates().all.n.deaths)
			local reset
			for _, init in ipairs(mock.settings.registered.layout.initializers) do
				if init.kind == "button" and init.name == "Reset my stats" then
					reset = init
				end
			end
			reset.onClick()
			assert.are.same({ "LOOSERPIML_RESET_STATS" }, mock.popups)
			assert.are.equal(1, stats:GetAggregates().all.n.deaths) -- nothing deleted yet
			mock.env.StaticPopupDialogs.LOOSERPIML_RESET_STATS.OnAccept()
			assert.is_nil(stats:GetAggregates().all.n.deaths)
		end)

		it("testing buttons work and respect test mode", function()
			local mock, ns = H.client()
			local buttons = {}
			for _, init in ipairs(mock.settings.registered.layout.initializers) do
				if init.kind == "button" then
					buttons[init.name] = init
				end
			end
			buttons["Fill with sample friends"].onClick()
			assert.is_true(mock:ChatContains("only run in test mode"))
			mock.settings.byVariable.LooserPiml_test_mode:SetValue(true)
			assert.is_true(ns.TestMode:IsEnabled())
			buttons["Fill with sample friends"].onClick()
			assert.is_true(mock:ChatContains("Sample friends added"))
			buttons["Simulate a death"].onClick()
			mock:Advance(2)
			assert.matches("Max died", H.lastRendered(mock))
			buttons["Show debug log"].onClick()
			assert.is_true(mock:ChatContains("log entries"))
		end)
	end)
end)
