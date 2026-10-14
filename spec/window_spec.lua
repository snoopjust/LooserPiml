local H = require("helpers")

local function window(mock)
	return mock.ns.Window
end

local function die(mock, times)
	for _ = 1, times or 1 do
		mock.player.dead = true
		mock:Fire("PLAYER_DEAD")
		mock.player.dead = false
		mock:Fire("PLAYER_UNGHOST")
	end
end

-- Tooltip recorder like GameTooltip
local function tooltip()
	local t = { lines = {} }
	function t:AddLine(text)
		self.lines[#self.lines + 1] = H.stripColors(tostring(text))
	end
	function t:has(fragment)
		for _, line in ipairs(self.lines) do
			if line:find(fragment, 1, true) then
				return true
			end
		end
		return false
	end
	return t
end

describe("Main window", function()
	after_each(H.checkClients)

	it("opens with /lp stats, closes with ESC (UISpecialFrames) and toggles", function()
		local mock, ns = H.client()
		ns.Slash:Dispatch("stats")
		local w = window(mock)
		assert.is_true(w:IsShown())
		assert.are.equal(w.frame, mock.env.LooserPimlMainFrame)
		local inSpecial = false
		for _, name in ipairs(mock.env.UISpecialFrames) do
			inSpecial = inSpecial or name == "LooserPimlMainFrame"
		end
		assert.is_true(inSpecial)
		assert.is_true(H.hasText(w.frame, "LooserPiml · Friends"))
		w:Toggle()
		assert.is_false(w:IsShown())
	end)

	it("shows the Leaderboard tab first, then Friends", function()
		local mock = H.client()
		window(mock):Open()
		local buttons = window(mock).frame.tabButtons
		assert.are.equal(2, #buttons)
		assert.are.equal("leaderboard", buttons[1].tabId)
		assert.are.equal("friends", buttons[2].tabId)
		assert.is_true(buttons[1].selected)
	end)

	it("saves the position after dragging", function()
		local mock = H.client()
		local w = window(mock)
		w:Open()
		w.frame:ClearAllPoints()
		w.frame:SetPoint("TOPLEFT", mock.env.UIParent, "TOPLEFT", 50, -80)
		w.frame.scripts.OnDragStop(w.frame)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 50, -80 }, mock.env.LooserPimlDB.window.point)
	end)

	describe("leaderboard tab", function()
		it("shows 'No one yet' cards and a hint when I'm alone", function()
			local mock = H.client()
			window(mock):Open()
			local frame = window(mock).frame
			assert.is_true(H.hasText(frame, "Everyone compared: who is best (or worst) at what"))
			assert.is_true(H.hasText(frame, "Death King"))
			assert.is_true(H.hasText(frame, "Speedrunner"))
			assert.is_true(H.hasText(frame, "No one yet"))
			assert.is_true(H.hasText(frame, "Add your friends in the Friends tab"))
		end)

		it("shows awards and the ranking from synced friends, updating live", function()
			local clients = H.group({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			window(me):Open()
			die(max, 3)
			die(me, 1)
			me:Advance(40)
			local frame = window(me).frame
			local texts = table.concat(H.texts(frame), "\n")
			assert.matches("Death King\nMax\n3", texts, 1, true)
			assert.matches("#1\nMax", texts, 1, true)
			assert.matches("#2\nMe %(you%)", texts)
			assert.is_false(H.hasText(frame, "Add your friends in the Friends tab"))
		end)

		it("switches period and metric with the selector buttons", function()
			local mock = H.client({ testMode = true })
			mock.ns:GetModule("Stats"):FillSampleFriends()
			local w = window(mock)
			w:Open()
			local tab = mock.ns:GetModule("Stats").LeaderboardTab
			local frame = w.frame.tabFrames.leaderboard
			frame.metricButtons[2]:Click() -- Gold (right now)
			assert.are.equal("gold", tab.metric)
			assert.is_true(frame.metricButtons[2].selected)
			assert.is_true(H.hasText(frame, "gold on hand right now"))
			assert.is_true(H.hasText(frame, "right now")) -- Gold Hoarder card value
			local goldRow = frame.rows[1].value.text_
			assert.is_truthy(goldRow:find("g", 1, true) and goldRow:find("right now$"), goldRow) -- "71g 60s right now"
			local function ranked()
				local n = 0
				for _, row in ipairs(frame.rows) do
					if row.shown then
						n = n + 1
					end
				end
				return n
			end
			assert.are.equal(4, ranked()) -- me + Max, Lena, Jo; Kim doesn't share gold
			frame.periodButtons[3]:Click() -- All time: still switches the cards
			assert.are.equal("all", tab.period)
			assert.is_true(frame.periodButtons[3].selected)
			assert.are.equal(4, ranked())
			frame.metricButtons[1]:Click() -- Deaths
			assert.is_false(H.hasText(frame, "gold on hand right now"))
			assert.are.equal(5, ranked()) -- me + 4 sample friends
		end)
	end)

	describe("minimap button and addon compartment", function()
		it("registers a LibDBIcon button: left-click toggles, right-click opens settings", function()
			local mock, ns = H.client()
			local button = mock.env.LibDBIcon10_LooserPiml
			assert.is_table(button)
			button:Click("LeftButton")
			assert.is_true(window(mock):IsShown())
			button:Click("LeftButton")
			assert.is_false(window(mock):IsShown())
			button:Click("RightButton")
			assert.are.equal(4242, mock.settings.opened)
			assert.are.equal(ns.Window.launcher, button.dataObject)
		end)

		it("tooltip shows hints, friends online, tonight's deaths and the Death King", function()
			local clients = H.group({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			die(max, 2)
			me:Advance(40)
			local tip = tooltip()
			window(me).launcher.OnTooltipShow(tip)
			assert.is_true(tip:has("LooserPiml"))
			assert.is_true(tip:has("Left-click"))
			assert.is_true(tip:has("Right-click"))
			assert.is_true(tip:has("Friends online with LooserPiml: 1"))
			assert.is_true(tip:has("Deaths tonight: 2"))
			assert.is_true(tip:has("Death King: Max (2)"))
		end)

		it("hides and shows the minimap button from the settings", function()
			local mock, ns = H.client()
			ns.Options:Set("minimap.show", false)
			assert.is_true(mock.env.LooserPimlDB.minimap.hide)
			assert.is_false(mock.env.LibDBIcon10_LooserPiml.shown)
			ns.Options:Set("minimap.show", true)
			assert.is_true(mock.env.LibDBIcon10_LooserPiml.shown)
		end)

		it("provides the Addon Compartment callbacks named in the .toc", function()
			local mock = H.client()
			local toc = io.open("LooserPiml.toc"):read("*a")
			for _, field in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
				local fn = toc:match("## " .. field .. ": (%S+)")
				assert.is_function(mock.env[fn], field)
			end
			mock.env.LooserPiml_OnAddonCompartmentClick("LooserPiml", "LeftButton")
			assert.is_true(window(mock):IsShown())
			mock.env.LooserPiml_OnAddonCompartmentEnter("LooserPiml", mock.env.UIParent)
			assert.is_true(#mock.env.GameTooltip.lines >= 3)
			mock.env.LooserPiml_OnAddonCompartmentLeave("LooserPiml")
		end)
	end)

	describe("footer", function()
		it("reports all friends current, or who is outdated", function()
			local clients = H.group({
				{ name = "Me", version = "v0.2.0" },
				{ name = "Max", class = "WARRIOR", version = "v0.2.0" },
				{ name = "Kim", class = "ROGUE", version = "v0.1.0" },
			})
			local me = clients[1]
			assert.matches("outdated: Kim %(v0.1.0%)", window(me):GetVersionStatus())
			local kim = clients[3]
			assert.matches("update available: v0.2.0", window(kim):GetVersionStatus())
			local solo = H.client({ version = "v0.2.0" })
			assert.matches("no LooserPiml friends online yet", window(solo):GetVersionStatus())
		end)
	end)
end)
