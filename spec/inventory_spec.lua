local H = require("helpers")

local function inv(mock)
	return mock.ns:GetModule("Inventory")
end

-- Decoded INV messages this client sent: { d = data, target }
local function invMessages(mock, msgType)
	local out = {}
	for _, call in ipairs(mock.sent) do
		local e = mock.ns.Comm:Decode(call.text)
		if e and e.t == (msgType or "INV") then
			out[#out + 1] = { d = e.d, target = call.target }
		end
	end
	return out
end

local function slots(list)
	local out = {}
	for i, entry in ipairs(list) do
		out[i] = { id = entry[1], count = entry[2] }
	end
	return out
end

describe("Inventory", function()
	after_each(H.checkClients)

	describe("collecting", function()
		it("counts bags per item ID, debounced after the last bag update", function()
			local mock, ns = H.client()
			local char = inv(mock):GetChar()
			mock:SetBag(0, slots({ { 2589, 20 }, { 2589, 5 }, { 118, 3 } }))
			mock:SetBag(1, slots({ { 2589, 7 } }))
			mock:Advance(1)
			assert.are.same({}, char.bags) -- still waiting for the bag events to settle
			mock:Advance(2)
			char = inv(mock):GetChar()
			assert.are.same({ [2589] = 32, [118] = 3 }, char.bags)
			mock:SetBag(5, slots({ { 2318, 4 } })) -- reagent bag
			mock:Advance(3)
			assert.are.equal(4, inv(mock):GetChar().bags[2318])
			H.assertNoErrors(mock)
		end)

		it("reads the bank only while it is open and keeps the last snapshot with its time", function()
			local mock = H.client()
			mock.containers[-2] = slots({ { 2319, 40 } })
			mock.containers[6] = slots({ { 2589, 100 } }) -- a bank bag
			mock:Fire("BAG_UPDATE_DELAYED")
			mock:Advance(3)
			assert.are.same({}, inv(mock):GetChar().bank) -- closed: unreadable, nothing wiped or invented
			mock:OpenBank()
			mock:Advance(1)
			local char = inv(mock):GetChar()
			assert.are.same({ [2319] = 40, [2589] = 100 }, char.bank)
			assert.is_number(char.bankAt)
			mock.containers[-2] = slots({ { 2319, 10 } })
			mock:Fire("PLAYERBANKSLOTS_CHANGED", 1)
			mock:Advance(3)
			assert.are.equal(10, inv(mock):GetChar().bank[2319])
			mock:CloseBank()
			mock:Advance(5)
			assert.are.equal(10, inv(mock):GetChar().bank[2319]) -- kept after closing
		end)

		it("skips slots it can't read (secret) instead of erroring", function()
			local mock = H.client()
			mock:SetBag(0, { { id = 2589, count = 2 }, { secret = true } })
			mock:Advance(3)
			assert.are.same({ [2589] = 2 }, inv(mock):GetChar().bags)
			H.assertNoErrors(mock)
		end)
	end)

	describe("sync between friends who are not grouped", function()
		it("sends a full snapshot after the handshake and deltas afterwards, at most every 30 s", function()
			local clients = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			max:SetBag(0, slots({ { 2589, 20 } }))
			max:Advance(5) -- full snapshot (after FULL_DELAY) and the first delta
			local cache = inv(me).db.friends["Max-TestRealm"]
			assert.is_table(cache)
			assert.are.equal(20, cache.bags[2589])

			local before = #invMessages(max)
			for i = 1, 5 do
				max:SetBag(0, slots({ { 2589, 20 + i } }))
				max:Advance(3)
			end
			max:Advance(40)
			local sent = invMessages(max)
			assert.is_true(#sent - before <= 2, "deltas sent: " .. (#sent - before))
			assert.is_nil(sent[#sent].d.f) -- a delta, not a full snapshot
			assert.are.equal(25, inv(me).db.friends["Max-TestRealm"].bags[2589])
			for _, m in ipairs(sent) do
				assert.are.equal("Me", m.target)
			end
		end)

		it("syncs the bank snapshot time and gold, and caches it for when the friend is offline", function()
			local clients = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			max.containers[-2] = slots({ { 2319, 40 } })
			max.money = 71 * 10000 + 60 * 100
			max:Fire("PLAYER_MONEY")
			max:OpenBank()
			me:Advance(40)
			local cache = inv(me).db.friends["Max-TestRealm"]
			assert.are.equal(40, cache.bank[2319])
			assert.is_number(cache.bankAt)
			assert.are.equal(716000, cache.gold)
			-- offline: still there with "seen"
			local saved = me.env.LooserPimlDB
			local mock2 = H.client({ savedVariables = saved })
			local holder
			for _, h in ipairs(inv(mock2):GetHolders()) do
				if h.name == "Max-TestRealm" then
					holder = h
				end
			end
			assert.is_table(holder)
			assert.is_false(holder.online)
			assert.are.equal(40, holder.bank[2319])
			assert.is_number(holder.seen)
		end)

		it("sharing off: nothing of that kind is sent, and friends drop what they had", function()
			local clients = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			max:SetBag(0, slots({ { 2589, 20 } }))
			max.money = 50000
			max:Fire("PLAYER_MONEY")
			me:Advance(40)
			assert.is_table(inv(me).db.friends["Max-TestRealm"].bags)

			max.ns.Options:Set("inventory.share", false)
			me:Advance(5)
			local cache = inv(me).db.friends["Max-TestRealm"]
			assert.is_nil(cache.bags)
			assert.is_nil(cache.bank)
			assert.are.equal(50000, cache.gold) -- gold is a separate switch
			local mark = #max.sent
			max:SetBag(0, slots({ { 2589, 99 }, { 118, 1 } }))
			max:Advance(40)
			for i = mark + 1, #max.sent do
				local e = max.ns.Comm:Decode(max.sent[i].text)
				if e and e.t == "INV" then
					assert.is_nil(e.d.i)
					assert.is_nil(e.d.b)
				end
			end

			max.ns.Options:Set("inventory.shareGold", false)
			me:Advance(5)
			assert.is_nil(inv(me).db.friends["Max-TestRealm"].gold)
		end)

		it("asks for a full snapshot when a delta doesn't fit, and gets one", function()
			local clients = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			max:SetBag(0, slots({ { 2589, 20 } }))
			me:Advance(40)
			inv(me).db.friends["Max-TestRealm"].seq = 999 -- pretend we missed a message
			max:SetBag(0, slots({ { 2589, 30 } }))
			me:Advance(40)
			assert.are.equal(1, #invMessages(me, "INVREQ"))
			assert.are.equal(30, inv(me).db.friends["Max-TestRealm"].bags[2589])
		end)

		it("drops hostile payloads", function()
			local mock, ns = H.client({ confirmed = { "Max" } })
			local function send(data, id)
				mock:Fire("CHAT_MSG_ADDON", "LPiml", ns.Comm:Encode({ v = 1, t = "INV", s = 9, id = id, d = data }), "WHISPER", "Max-TestRealm")
			end
			send("nope", 1)
			send({ f = true, s = 1, q = 0, i = { b = { [2589] = -4, [-1] = 3, ["x"] = 1, [118] = 1e12, [2318] = 2.5 }, k = "bank" }, g = "lots" }, 2)
			local cache = inv(mock).db.friends["Max-TestRealm"]
			assert.are.same({ [2318] = 2 }, cache.bags)
			assert.are.same({}, cache.bank)
			assert.is_nil(cache.gold)
			H.assertNoErrors(mock)
		end)
	end)

	it("keeps a full bag-and-bank snapshot within a few chunks", function()
		local mock, ns = H.client()
		-- Realistic spread: item IDs anywhere from 700 to 25000, counts 1..200.
		local x = 4242
		local function rand(low, high)
			x = (x * 1103515245 + 12345) % 2147483648
			return low + math.floor(x / 65536) % (high - low + 1)
		end
		local bags, bank = {}, {}
		for _ = 1, 120 do
			bags[#bags + 1] = { id = rand(700, 25000), count = rand(1, 20) }
		end
		for _ = 1, 180 do
			bank[#bank + 1] = { id = rand(700, 25000), count = rand(1, 200) }
		end
		mock.containers[0] = bags
		mock.containers[-2] = bank
		mock:OpenBank()
		mock:Advance(3)
		local inventory = inv(mock)
		local payload = { f = true, s = 1, q = 0, a = 1760000000, g = 12345678 }
		local state = inventory:CurrentState()
		payload.i = { b = state.bags, k = state.bank, ka = state.bankAt }
		local bytes = #ns.Comm:Encode({ v = 1, t = "INV", s = 1, id = 1, d = payload })
		local chunks = math.ceil(bytes / 254)
		print(string.format("\n[size] full inventory snapshot: 120 bag items + 180 bank items = %d bytes on the wire, %d chunks", bytes, chunks))
		assert.is_true(chunks <= 12, "snapshot needs " .. chunks .. " chunks")
	end)
end)

describe("Inventory tab", function()
	after_each(H.checkClients)

	local function open(mock)
		mock.ns:GetModule("Stats"):FillSampleFriends()
		mock.ns.Window:Open("inventory")
		return mock.ns.Window.frame.tabFrames.inventory
	end

	local function shownRows(frame)
		local out = {}
		for _, row in ipairs(frame.itemsView.rows) do
			if row.shown then
				out[#out + 1] = H.stripColors(row.name.text_) .. " " .. row.total.text_
			end
		end
		return out
	end

	it("lists items by total, highest first, with one chip per holder and a bank tag", function()
		local mock = H.client({ testMode = true })
		local frame = open(mock)
		assert.is_true(H.hasText(frame, "Friends' inventory"))
		assert.is_true(H.hasText(frame, "Bags and banks of your LooserPiml friends, updated automatically"))
		local rows = shownRows(frame)
		assert.are.equal("Linen Cloth 108", rows[1]) -- Max 40 + 60 (bank) + Jo 8
		local chips = H.texts(frame.itemsView.rows[1])
		assert.is_true(table.concat(chips, "|"):find("Max 100 bank", 1, true) ~= nil)
		assert.is_true(H.hasText(frame, "items held by"))
		mock.ns.TestMode:Disable()
	end)

	it("searches by item name as you type and filters by category and location", function()
		local mock = H.client({ testMode = true })
		local frame = open(mock)
		local tab = mock.ns:GetModule("Inventory").InventoryTab
		frame.itemsView.search:SetText("leather")
		frame.itemsView.search.scripts.OnTextChanged(frame.itemsView.search)
		assert.are.same({ "Medium Leather 74", "Light Leather 42" }, shownRows(frame))
		assert.is_true(H.hasText(frame, "2 items held by 3 friends"))
		frame.itemsView.locationButtons[3]:Click() -- Bank
		assert.are.same({ "Medium Leather 68", "Light Leather 30" }, shownRows(frame))
		frame.itemsView.search:SetText("")
		frame.itemsView.search.scripts.OnTextChanged(frame.itemsView.search)
		frame.itemsView.locationButtons[1]:Click()
		frame.itemsView.categoryButtons[3]:Click() -- Consumables
		assert.are.same({ "Minor Healing Potion 7" }, shownRows(frame))
		frame.itemsView.categoryButtons[4]:Click() -- Gear
		assert.are.same({ "Carving Knife 1" }, shownRows(frame))
		assert.are.equal("gear", tab.category)
		mock.ns.TestMode:Disable()
	end)

	it("loads uncached item names asynchronously and refreshes the row", function()
		local mock = H.client({ testMode = true })
		local frame = open(mock)
		local inventory = mock.ns:GetModule("Inventory")
		frame.itemsView.categoryButtons[2]:Click() -- Materials
		local texts = table.concat(H.texts(frame.itemsView), "|")
		assert.is_true(texts:find("Loading", 1, true) ~= nil) -- Silk Cloth isn't cached yet
		assert.is_true(mock.itemLoads >= 1)
		mock:Advance(2)
		texts = table.concat(H.texts(frame.itemsView), "|")
		assert.is_true(texts:find("Silk Cloth", 1, true) ~= nil)
		assert.are.equal("Silk Cloth", inventory.Items.Info(4306).name)
		mock.ns.TestMode:Disable()
	end)

	it("shows the 'none of your friends has this' hint with a wishlist button", function()
		local mock = H.client({ testMode = true })
		local frame = open(mock)
		frame.itemsView.search:SetText("Arcanite Bar")
		frame.itemsView.search.scripts.OnTextChanged(frame.itemsView.search)
		assert.are.same({}, shownRows(frame))
		assert.is_true(H.hasText(frame, "None of your friends has this yet. Add it to your wishlist"))
		assert.is_true(frame.itemsView.emptyAdd.shown)
		mock.ns.TestMode:Disable()
	end)

	it("gold bar: a chip per friend who shares gold, stale marker when offline, and a total", function()
		local mock = H.client({ testMode = true })
		mock.money = 50000
		local frame = open(mock)
		local chips = {}
		for _, chip in ipairs(frame.goldChips) do
			if chip.shown then
				chips[#chips + 1] = H.stripColors(chip.text.text_)
			end
		end
		assert.are.equal("Lena 125g", chips[1])
		assert.are.equal("Max 71g 60s", chips[2])
		assert.is_true(chips[#chips]:find("^Total") ~= nil)
		for _, chip in ipairs(chips) do
			assert.is_nil(chip:find("Kim", 1, true)) -- doesn't share gold
		end
		assert.are.equal(125 * 10000 + 716000 + 98000 + 50000, frame.goldTotal)
		mock.ns.TestMode:Disable()
	end)

	it("last updated: 'bags now · bank 3 days ago' or 'offline · last seen ...'", function()
		local mock = H.client({ testMode = true })
		local frame = open(mock)
		local text = table.concat(H.texts(frame.itemsView), "|")
		assert.is_true(text:find("bags now · bank 3 days ago", 1, true) ~= nil)
		assert.is_true(text:find("offline · last seen", 1, true) ~= nil)
		assert.is_true(H.hasText(frame, "Banks update when their owner opens the bank."))
		mock.ns.TestMode:Disable()
	end)

	it("has no button that would message a friend", function()
		local mock = H.client({ testMode = true })
		local frame = open(mock)
		for _, text in ipairs(H.texts(frame)) do
			local lower = text:lower()
			assert.is_nil(lower:find("whisper", 1, true))
			assert.is_nil(lower:find("ask ", 1, true))
		end
		mock.ns.TestMode:Disable()
	end)
end)
