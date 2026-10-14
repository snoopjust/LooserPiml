local H = require("helpers")

local function inv(mock)
	return mock.ns:GetModule("Inventory")
end

local LEATHER_LINK = "|cffffffff|Hitem:2319::::::::10:::::::|h[Medium Leather]|h|r"

local function loot(mock, link, count)
	local text = count and ("You receive loot: " .. link .. "x" .. count .. ".") or ("You receive loot: " .. link .. ".")
	mock:Fire("CHAT_MSG_LOOT", text, mock.player.name)
end

describe("Wishlist", function()
	after_each(H.checkClients)

	describe("my own list", function()
		it("adds by typed name, item link or ID, updates the quantity of a repeat, removes", function()
			local mock = H.client()
			local inventory = inv(mock)
			assert.are.equal(2589, (inventory:AddWish("linen cloth", "20")))
			assert.are.equal(2319, (inventory:AddWish(LEATHER_LINK, 10)))
			assert.are.equal(118, (inventory:AddWish("118", 3)))
			assert.are.equal(3, #inventory:GetWishlist())
			inventory:AddWish("Linen Cloth", 40)
			assert.are.equal(3, #inventory:GetWishlist())
			assert.are.equal(40, inventory:GetWishlist()[1].n)
			local id, err = inventory:AddWish("Thunderfury", 1)
			assert.is_nil(id)
			assert.matches("Unknown item", err)
			id, err = inventory:AddWish("Linen Cloth", "lots")
			assert.is_nil(id)
			assert.matches("quantity", err)
			assert.is_true(inventory:RemoveWish(118))
			assert.is_false(inventory:RemoveWish(118))
			assert.are.equal(2, #inventory:GetWishlist())
		end)

		it("takes a shift-clicked item link into the wishlist box", function()
			local mock = H.client()
			local inserted = {}
			mock.env.ChatFrameUtil = {
				InsertLink = function(link)
					inserted[#inserted + 1] = link
					return false
				end,
			}
			mock.ns.Window:Open("inventory")
			local frame = mock.ns.Window.frame.tabFrames.inventory
			frame.viewButtons[2]:Click() -- Wishlists
			local box = frame.wishView.input
			box.HasFocus = function()
				return true
			end
			mock.env.ChatFrameUtil.InsertLink(LEATHER_LINK) -- what a shift-click calls
			assert.are.equal(LEATHER_LINK, box:GetText())
			assert.are.equal(1, #inserted) -- Blizzard's function still ran (post-hook)
			frame.wishView.quantity:SetText("5")
			frame.wishView.add:Click()
			assert.are.equal(2319, inv(mock):GetWishlist()[1].id)
			assert.are.equal(5, inv(mock):GetWishlist()[1].n)
		end)
	end)

	describe("friends' lists", function()
		it("syncs to connected friends who are not grouped; only the owner can remove", function()
			local clients = H.friends({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			inv(max):AddWish("Medium Leather", 60)
			max:Advance(10)
			local entries = inv(me):GetWishEntries()
			assert.are.equal(1, #entries)
			assert.are.equal("Max-TestRealm", entries[1].owner)
			assert.are.equal(60, entries[1].wanted)
			me.ns.Window:Open("inventory")
			local frame = me.ns.Window.frame.tabFrames.inventory
			frame.viewButtons[2]:Click()
			local row = frame.wishView.rows[1]
			assert.is_true(H.hasText(row, "for Max"))
			assert.is_false(row.remove.shown) -- not mine: no remove button
			assert.is_true(H.hasText(frame, "Everyone adds only their own wishes; all friends can see them."))
		end)

		it("a received wishlist is stored under its sender only and can't be edited", function()
			local mock, ns = H.client({ confirmed = { "Max" } })
			local inventory = inv(mock)
			inventory:AddWish("Linen Cloth", 5)
			local text = ns.Comm:Encode({ v = 1, t = "WISH", s = 3, id = 1, d = {
				owner = "Me-TestRealm", -- pretends to be my list: ignored
				w = { { i = 2319, n = 60 }, { i = 2319, n = 1 }, { i = -1, n = 2 }, { i = 118, n = 1e9 }, "junk" },
			} })
			mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "WHISPER", "Max-TestRealm")
			assert.are.same({ { id = 2589, n = 5 } }, inventory:GetWishlist()) -- mine untouched
			assert.are.same({ { id = 2319, n = 60 } }, inventory.db.friends["Max-TestRealm"].wishlist)
			assert.is_false(inventory:RemoveWish(2319)) -- only works on my own list
			assert.are.same({ { id = 2319, n = 60 } }, inventory.db.friends["Max-TestRealm"].wishlist)
			H.assertNoErrors(mock)
		end)

		it("shows 'N among friends' (green when enough), 'looted tonight', 'no friend has it yet'", function()
			local mock = H.client({ testMode = true })
			mock.ns:GetModule("Stats"):FillSampleFriends()
			local inventory = inv(mock)
			inventory:AddWish("4306", 10) -- not cached yet: by ID
			inventory:AddWish("Carving Knife", 5)
			mock.ns.Timeline:Add({ s = "Max-TestRealm", k = "wishloot", id = 118, n = 3, x = "x" })
			inventory:AddWish("Minor Healing Potion", 100)
			local byKey = {}
			for _, entry in ipairs(inventory:GetWishEntries()) do
				byKey[entry.owner .. ":" .. entry.id] = entry
			end
			local Tab = inventory.InventoryTab
			assert.matches("20 among friends", Tab.WishStatus(byKey["Me-TestRealm:4306"]))
			assert.matches("ff40d040", Tab.WishStatus(byKey["Me-TestRealm:4306"])) -- green: enough
			assert.matches("1 among friends", Tab.WishStatus(byKey["Me-TestRealm:2140"]))
			assert.is_nil(Tab.WishStatus(byKey["Me-TestRealm:2140"]):find("40d040"))
			assert.are.equal("7 among friends · 3 looted tonight", H.stripColors(Tab.WishStatus(byKey["Me-TestRealm:118"])))
			-- Lena's own 0 don't count for her wish; Max 54 (bank) + Kim 20
			assert.matches("74 among friends", Tab.WishStatus(byKey["Lena-TestRealm:2319"]))
			inventory.sampleHolders = {}
			inventory:AddWish("Light Leather", 1)
			local entry
			for _, e in ipairs(inventory:GetWishEntries()) do
				if e.id == 2318 then
					entry = e
				end
			end
			assert.matches("no friend has it yet", Tab.WishStatus(entry))
			mock.ns.TestMode:Disable()
		end)
	end)

	describe("wishlist loot", function()
		it("a friend loots an item on my wishlist: banner on my screen, 'On your wishlist · 7 still needed'", function()
			local clients = H.friends({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			inv(me):AddWish("Medium Leather", 10)
			me:Advance(40)
			me.rendered = {}
			loot(max, LEATHER_LINK, 3)
			me:Advance(6)
			assert.are.equal("Max looted Medium Leather ×3 · On your wishlist · 7 still needed", H.lastRendered(me))
			assert.are.equal("Max looted Medium Leather ×3 · On Me's wishlist · 7 still needed", H.lastRendered(max))
			local timeline = me.ns.Timeline:Between(0)
			assert.are.equal("wishloot", timeline[#timeline].k)
			assert.are.equal(3, inv(me):LootedTonight(2319))
		end)

		it("names the friend whose wishlist it is, and respects the banner toggle and 'chat line only'", function()
			local clients = H.friends({
				{ name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE" },
			})
			local me, max, lena = clients[1], clients[2], clients[3]
			inv(lena):AddWish("Medium Leather", 10)
			me:Advance(40)
			me.rendered = {}
			loot(max, LEATHER_LINK, 3)
			me:Advance(6)
			assert.are.equal("Max looted Medium Leather ×3 · On Lena's wishlist · 7 still needed", H.lastRendered(me))

			me.ns.Options:Set("ticker.wishlist", false)
			me.rendered = {}
			loot(max, LEATHER_LINK)
			me:Advance(6)
			assert.are.equal(0, #me.rendered)
			assert.are.equal(4, inv(me):LootedTonight(2319)) -- still in the timeline

			me.ns.Options:Set("ticker.wishlist", true)
			me.ns.Options:Set("ticker.friends", "chat")
			local lines = #me.chat
			loot(max, LEATHER_LINK)
			me:Advance(6)
			assert.are.equal(0, #me.rendered)
			assert.are.equal(lines + 1, #me.chat)
			assert.is_true(me.chat[#me.chat]:find("Lena", 1, true) ~= nil)
		end)

		it("ignores loot that is on nobody's wishlist", function()
			local mock = H.client({ confirmed = { "Max" } })
			mock.sent = {}
			loot(mock, LEATHER_LINK, 2)
			mock:Advance(5)
			assert.are.equal(0, #mock.rendered)
			for _, call in ipairs(mock.sent) do
				local e = mock.ns.Comm:Decode(call.text)
				assert.are_not.equal("TICK", e and e.t)
			end
		end)
	end)
end)
