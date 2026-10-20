local H = require("helpers")

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

local function ticker(mock)
	return mock.ns:GetModule("Ticker")
end

-- winner challenges loser; both pick `choice`; the duel ends with `text`
local function duel(net, winner, loser, choice, text)
	winner:ChallengeToDuel(loser.player.name)
	loser:DuelRequested(winner.player.name)
	net:Advance(1)
	stats(winner).DuelPanel.frame[choice]:Click()
	stats(loser).DuelPanel.frame[choice]:Click()
	loser:AcceptDuelRequest()
	net:Advance(5)
	text = text or (winner.player.name .. " has defeated " .. loser.player.name .. " in a duel")
	winner:DuelEnded(text)
	loser:DuelEnded(text)
	net:Advance(1)
end

local function trio()
	local clients, net = H.friends({
		{ name = "Lootius", class = "ROGUE" }, { name = "Nerdalot", class = "MAGE" }, { name = "Lena", class = "PRIEST" },
	})
	return clients[1], clients[2], clients[3], net
end

local function chatWith(mock, fragment)
	for _, line in ipairs(mock.chat) do
		local plain = H.stripColors(line)
		if plain:find(fragment, 1, true) then
			return plain
		end
	end
	return nil
end

describe("Ranked duels: banner, tab, settings", function()
	after_each(H.checkClients)

	describe("ticker", function()
		it("shows one banner after a ranked duel to all connected friends, nobody grouped", function()
			local lootius, nerdalot, lena, net = trio()
			duel(net, lootius, nerdalot, "ranked")
			duel(net, lootius, nerdalot, "ranked")
			local expected = "Lootius won a ranked duel against Nerdalot · Ranked head to head: Lootius 2 – 0 Nerdalot"
			for _, mock in ipairs({ lootius, nerdalot, lena }) do
				local last = H.lastRendered(mock)
				assert.is_truthy(last and last:find(expected, 1, true), mock.player.name .. ": " .. tostring(last))
			end
			-- exactly one banner per duel on the third friend's screen (the loser sends nothing)
			local count = 0
			for _, text in ipairs(H.renderedPlain(lena)) do
				if text:find("ranked duel", 1, true) then
					count = count + 1
				end
			end
			assert.are.equal(2, count)
			for _, msg in ipairs(H.decodedSent(nerdalot)) do
				assert.is_false(msg.t == "TICK" and msg.d.k:find("^duel") ~= nil)
			end
		end)

		it("says who fled", function()
			local lootius, nerdalot, lena, net = trio()
			duel(net, lootius, nerdalot, "ranked", "Nerdalot has fled from Lootius in a duel")
			assert.is_truthy(H.lastRendered(lena):find("Lootius won a ranked duel against Nerdalot (Nerdalot fled)", 1, true))
		end)

		it("shows nothing for fun duels by default, a chat line (never a banner) with the setting", function()
			local lootius, nerdalot, lena, net = trio()
			local before = #lena.rendered
			duel(net, lootius, nerdalot, "fun")
			assert.are.equal(before, #lena.rendered)
			assert.is_nil(chatWith(lena, "in a duel"))
			ticker(lena).db.show.duelFun = true
			ticker(lootius).db.show.duelFun = true
			duel(net, lootius, nerdalot, "fun")
			assert.are.equal(before, #lena.rendered)
			assert.is_truthy(chatWith(lena, "Lootius beat Nerdalot in a duel (just for fun)"))
			assert.is_truthy(chatWith(lootius, "Lootius beat Nerdalot in a duel (just for fun)"))
		end)

		it("turns the ranked banner off with 'Ranked duel results'", function()
			local lootius, nerdalot, lena, net = trio()
			ticker(lena).db.show.duelRanked = false
			local before = #lena.rendered
			duel(net, lootius, nerdalot, "ranked")
			assert.are.equal(before, #lena.rendered)
			assert.is_truthy(H.lastRendered(nerdalot):find("ranked duel", 1, true))
		end)

		it("sanitizes received duel events", function()
			local mock = H.client({ confirmed = { "Max" } })
			local t = ticker(mock)
			assert.is_nil(t:Sanitize({ k = "duel_ranked" })) -- no opponent
			local clean = t:Sanitize({ k = "duel_ranked", o = "Lena", oc = "lower", w = -3, l = "x", fl = 1 })
			assert.are.same({ k = "duel_ranked", o = "Lena-TestRealm", w = 0, l = 0 }, clean)
			assert.is_nil(t:Sanitize({ k = "duel_fun", o = "|cffffffffX|r" }))
		end)

		it("/lp sim duel shows a [test] banner after the simulated duel", function()
			local mock, ns = H.client({ testMode = true })
			ns.Slash:Dispatch("sim duel Max fled")
			mock:Advance(1.5)
			stats(mock).DuelPanel.frame.ranked:Click()
			mock:Advance(12)
			local last = H.lastRendered(mock)
			assert.is_truthy(last:find("[test]", 1, true))
			assert.is_truthy(last:find("won a ranked duel against Max (Max fled)", 1, true), last)
			ns.Slash:Dispatch("sim duel Lena fun")
			mock:Advance(1.5)
			stats(mock).DuelPanel.frame.ranked:Click()
			mock:Advance(12)
			assert.are.equal(last, H.lastRendered(mock)) -- fun: no banner
			assert.are.equal(0, #mock.sent)
		end)
	end)

	describe("PvP tab", function()
		local function open(mock)
			local w = mock.ns.Window
			w:Open("pvp")
			return w.frame.tabFrames.pvp
		end

		it("shows the ladder, the head to head matrix and the battleground placeholder", function()
			local mock = H.client({ testMode = true })
			stats(mock):FillSampleFriends()
			local frame = open(mock)
			local texts = table.concat(H.texts(frame), "\n")
			assert.is_truthy(texts:find("Duels between LooserPiml friends", 1, true))
			assert.is_truthy(texts:find("Battlegrounds – coming later", 1, true))
			-- Max: 6 wins, 3 losses, 67 %, last three duels won (the disputed one left out)
			assert.is_truthy(texts:find("#1\nMax\n6\n3\n67%\nW3", 1, true), texts)
			assert.is_truthy(texts:find("#4\nKim\n1\n2\n33%\nL2", 1, true))
			assert.is_truthy(texts:find("W – L", 1, true))
			assert.is_truthy(texts:find("—", 1, true)) -- diagonal
			local tab = stats(mock).PvPTab
			assert.are.equal("ranked", tab.mode)
			-- Matrix order: most duels first -> Max, Lena, Jo, Kim. Max beat Lena 3x (ranked).
			local maxRow = frame.matrixRows[1]
			assert.are.equal("Max", H.stripColors(maxRow.name.text_))
			assert.are.equal("3", maxRow.cells[2].text_)
			assert.is_true(maxRow.heat[2].shown) -- the highest value is highlighted
			frame.modeButtons[2]:Click() -- All duels: incl. the fun ones (Lena beat Max once more)
			assert.are.equal("all", tab.mode)
			assert.is_true(frame.modeButtons[2].selected)
			-- rows and columns are in the same order; find Lena's row and Max's column
			local function index(name)
				for i, row in ipairs(frame.matrixRows) do
					if row.name.text_ and H.stripColors(row.name.text_) == name then
						return i
					end
				end
			end
			assert.are.equal("2", frame.matrixRows[index("Lena")].cells[index("Max")].text_)
			frame.modeButtons[1]:Click()
			assert.are.equal("1", frame.matrixRows[index("Lena")].cells[index("Max")].text_)
			-- W – L right after the fourth player's column, not after seven
			local tab = stats(mock).PvPTab
			local _, x = frame.totalHeader:GetPoint(1) -- SetPoint("TOPLEFT", x, y)
			assert.are.equal(4 + tab.NAME_WIDTH + 4 * tab.CELL_WIDTH, x)
			local _, rowX = frame.matrixRows[1].total:GetPoint(1)
			assert.are.equal(x, rowX)
		end)

		it("shows hints when there are no duels yet", function()
			local mock = H.client()
			local frame = open(mock)
			assert.is_true(H.hasText(frame, "No ranked duels yet"))
			assert.is_true(H.hasText(frame, "No duels between your LooserPiml friends yet"))
		end)

		it("is a tab between Profiles and Friends", function()
			local mock = H.client()
			local ids = {}
			for _, tab in ipairs(mock.ns.Window.tabs) do
				ids[#ids + 1] = tab.id
			end
			assert.are.same({ "leaderboard", "tonight", "inventory", "profiles", "pvp", "friends" }, ids)
		end)
	end)

	describe("settings", function()
		it("has the three duel settings in the Ticker section with the right defaults", function()
			local mock, ns = H.client()
			local keys = {}
			for _, section in ipairs(ns.Options.sections) do
				if section.id == "ticker" then
					for _, item in ipairs(section.items) do
						if item.key then
							keys[item.key] = item
						end
					end
				end
			end
			assert.is_true(keys["ticker.duelRanked"].default)
			assert.is_false(keys["ticker.duelFun"].default)
			assert.is_true(keys["duels.ask"].default)
			assert.is_true(ns.Options:Get("ticker.duelRanked"))
			assert.is_false(ns.Options:Get("ticker.duelFun"))
			assert.is_true(ns.Options:Get("duels.ask"))
			ns.Options:Set("duels.ask", false)
			assert.is_false(stats(mock).db.askRanked)
		end)
	end)
end)
