-- Wishlists: everyone keeps their own list of wanted items (item +
-- quantity) and sees their friends' lists.
--
-- Each player edits only their OWN list. Friends' lists arrive as WISH
-- messages and are stored under the sender's name only: a message can't
-- touch anyone else's list (there is no "owner" field to trust), and
-- there is no function that edits a friend's list.
--
-- WISH payload: { w = { { i = itemID, n = wanted }, ... } }   (the whole list)
-- Sent to connected friends after their handshake and WISH_DELAY seconds
-- after a change.
--
-- Wishlist loot: when we loot an item that is on anyone's wishlist (ours
-- or a friend's), LP_WISHLIST_LOOT goes to the Ticker, which shows it and
-- sends it to our friends as a "wishloot" ticker event.
local _, ns = ...
local L = ns.L

local Inventory = ns:GetModule("Inventory")
local Window = ns.Window
local Items = Inventory.Items
local THEME = Window.THEME
local Tab = Inventory.InventoryTab

Inventory.WISH_MSG = "WISH"
Inventory.WISH_DELAY = 5     -- seconds after a change before the list is sent
Inventory.MAX_WISHES = 30
Inventory.MAX_WANTED = 10000

----------------------------------------------------------------------
-- My wishlist
----------------------------------------------------------------------

function Inventory:GetWishlist()
	return self:GetChar().wishlist
end

-- Item ID from what the player typed: an item link (shift-click), an item
-- ID, or a name the client knows (its own item cache, or an item anyone of
-- us holds). nil if unknown.
function Inventory:ResolveItem(input)
	if type(input) ~= "string" then
		return nil
	end
	input = input:gsub("^%s+", ""):gsub("%s+$", "")
	local id = ns.Util.ItemIDFromLink(input) or tonumber(input:match("^#?(%d+)$"))
	if id then
		return id
	end
	if input == "" then
		return nil
	end
	local api = C_Item or {}
	if api.GetItemInfoInstant then
		local found = api.GetItemInfoInstant(input) -- works for names in the client's cache
		if type(found) == "number" and not ns.IsSecret(found) then
			return found
		end
	end
	local wanted = input:lower()
	for _, holder in ipairs(self:GetHolders()) do
		for _, map in ipairs({ holder.bags or {}, holder.bank or {} }) do
			for itemID in pairs(map) do
				local info = Items.Info(itemID)
				if info.name and info.name:lower() == wanted then
					return itemID
				end
			end
		end
	end
	return nil
end

-- Returns the item ID, or nil plus a message for the player.
function Inventory:AddWish(input, quantity)
	local id = self:ResolveItem(input)
	if not id then
		return nil, L.WISH_ERR_UNKNOWN
	end
	if quantity == nil or quantity == "" then
		quantity = 1
	end
	quantity = tonumber(quantity)
	if not quantity or quantity ~= quantity or quantity < 1 or quantity > self.MAX_WANTED then
		return nil, L.WISH_ERR_QUANTITY
	end
	quantity = math.floor(quantity)
	local list = self:GetWishlist()
	for _, wish in ipairs(list) do
		if wish.id == id then
			wish.n = quantity -- same item again: new quantity
			self:WishlistChanged()
			return id
		end
	end
	if #list >= self.MAX_WISHES then
		return nil, L.WISH_ERR_FULL:format(self.MAX_WISHES)
	end
	list[#list + 1] = { id = id, n = quantity }
	Items.Info(id) -- start loading the name
	self:WishlistChanged()
	return id
end

function Inventory:RemoveWish(id)
	local list = self:GetWishlist()
	for i = #list, 1, -1 do
		if list[i].id == id then
			table.remove(list, i)
			self:WishlistChanged()
			return true
		end
	end
	return false
end

function Inventory:WishlistChanged()
	ns.Events:Fire("LP_WISHLIST_CHANGED")
	self.wishToken = (self.wishToken or 0) + 1
	local token = self.wishToken
	C_Timer.After(self.WISH_DELAY, function()
		if token == self.wishToken then
			self:SendWishlist(nil)
		end
	end)
end

function Inventory:SendWishlist(names)
	if not self:IsEnabled() then
		return "off"
	end
	local items = {}
	for _, wish in ipairs(self:GetWishlist()) do
		items[#items + 1] = { i = wish.id, n = wish.n }
	end
	return ns.Comm:Send(self.WISH_MSG, { w = items }, { scope = "friends", to = names, prio = "BULK" })
end

-- After a friend's handshake (together with the inventory snapshot).
function Inventory:QueueWishlist(name)
	self.wishQueue = self.wishQueue or {}
	self.wishQueue[#self.wishQueue + 1] = name
	if self.wishScheduled then
		return
	end
	self.wishScheduled = true
	C_Timer.After(self.FULL_DELAY, function()
		self.wishScheduled = false
		local names = self.wishQueue
		self.wishQueue = {}
		self:SendWishlist(names)
	end)
end

----------------------------------------------------------------------
-- Friends' wishlists
----------------------------------------------------------------------

-- Stored under the sender only. Untrusted: whole numbers, capped.
function Inventory:OnWishMessage(data, sender, meta)
	if meta.test or type(data) ~= "table" or type(data.w) ~= "table" then
		return
	end
	local clean, seen = {}, {}
	for _, wish in ipairs(data.w) do
		if #clean >= self.MAX_WISHES then
			break
		end
		if type(wish) == "table" then
			local id, n = wish.i, wish.n
			if type(id) == "number" and id == math.floor(id) and id > 0 and id < 10000000 and not seen[id]
				and type(n) == "number" and n == n and n >= 1 and n <= self.MAX_WANTED then
				seen[id] = true
				clean[#clean + 1] = { id = id, n = math.floor(n) }
			end
		end
	end
	local cache = self.db.friends[sender] or {}
	cache.wishlist = clean
	cache.seen = time()
	self.db.friends[sender] = cache
	ns.Events:Fire("LP_WISHLIST_CHANGED", sender)
end

-- How many of an item the others hold for this wish: everyone except the
-- owner (what friends could hand over); for my own wish everyone incl. me.
local function heldFor(holders, owner, id)
	local total = 0
	for _, holder in ipairs(holders) do
		if holder.name ~= owner or holder.isSelf then
			total = total + ((holder.bags or {})[id] or 0) + ((holder.bank or {})[id] or 0)
		end
	end
	return total
end

-- Times an item was looted (by anyone) as wishlist loot tonight.
function Inventory:LootedTonight(id, now)
	local start = ns.Util.GamingDayStart(now or GetServerTime())
	local count = 0
	for _, entry in ipairs(ns.Timeline:Between(start)) do
		if entry.k == "wishloot" and entry.id == id then
			count = count + (entry.n or 1)
		end
	end
	return count
end

-- All wishes, mine first: { owner, class, isSelf, id, info, wanted, have,
-- enough, lootedTonight }.
function Inventory:GetWishEntries(holders)
	holders = holders or self:GetHolders()
	local entries = {}
	for _, holder in ipairs(holders) do
		for _, wish in ipairs(holder.wishlist or {}) do
			local have = heldFor(holders, holder.name, wish.id)
			entries[#entries + 1] = {
				owner = holder.name, class = holder.class, isSelf = holder.isSelf == true,
				id = wish.id, info = Items.Info(wish.id), wanted = wish.n, have = have, enough = have >= wish.n,
				lootedTonight = self:LootedTonight(wish.id),
			}
		end
	end
	table.sort(entries, function(a, b)
		if a.isSelf ~= b.isSelf then
			return a.isSelf
		end
		if a.owner ~= b.owner then
			return a.owner < b.owner
		end
		return a.id < b.id
	end)
	return entries
end

----------------------------------------------------------------------
-- Wishlist loot
----------------------------------------------------------------------

-- Our own loot message: is the item on anyone's wishlist?
function Inventory:OnChatMsgLoot(_, text)
	local kind, link, count = ns.Util.ParseOwnLoot(text)
	if kind ~= "loot" then
		return
	end
	local id = ns.Util.ItemIDFromLink(link)
	if not id then
		return
	end
	local holders = self:GetHolders()
	local best
	for _, holder in ipairs(holders) do
		if not holder.fake then
			for _, wish in ipairs(holder.wishlist or {}) do
				if wish.id == id then
					-- Our bags aren't rescanned yet: the new items count on top.
					local have = heldFor(holders, holder.name, id) + count
					local need = math.max(0, wish.n - have)
					if not best or need > best.need then
						best = { owner = holder.name, need = need }
					end
				end
			end
		end
	end
	if not best then
		return
	end
	local info = Items.Info(id)
	ns.Events:Fire("LP_WISHLIST_LOOT", {
		id = id, n = count, nm = info.name or link:match("%[(.-)%]"), q = info.quality or ns.Util.ItemQuality(link),
		o = best.owner, need = best.need,
	})
end

----------------------------------------------------------------------
-- Wishlists view of the Inventory tab
----------------------------------------------------------------------

Tab.MAX_WISH_ROWS = 8

-- Shift-clicking an item while the wishlist box has focus puts its link
-- there. The game routes shift-clicks through ChatFrameUtil.InsertLink
-- (Midnight-style UI) or ChatEdit_InsertLink (older); we only post-hook
-- them (hooksecurefunc) and never change what they do.
-- TODO(verify in-game): which of the two Forever calls for item links.
local hooked = false
local function hookLinkInsert(box)
	if hooked then
		return
	end
	local function insert(link)
		if box:IsVisible() and box.HasFocus and box:HasFocus() and type(link) == "string" and ns.Util.ItemIDFromLink(link) then
			box:SetText(link)
		end
	end
	if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insert)
		hooked = true
	elseif type(ChatEdit_InsertLink) == "function" then
		hooksecurefunc("ChatEdit_InsertLink", insert)
		hooked = true
	end
end

function Tab:CreateWishRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(720, 26)
	row:SetPoint("TOPLEFT", 0, -160 - (index - 1) * 28)
	row.border = Window:CreatePanel(row)
	row.border:SetSize(22, 22)
	row.border:SetPoint("LEFT", 2, 0)
	row.icon = row.border:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 2, -2)
	row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	row.name = Window:CreateText(row, "GameFontHighlight", THEME.text)
	row.name:SetPoint("LEFT", 30, 0)
	row.name:SetWidth(220)
	row.owner = Window:CreateText(row, "GameFontHighlightSmall", THEME.muted)
	row.owner:SetPoint("LEFT", 256, 0)
	row.owner:SetWidth(150)
	row.status = Window:CreateText(row, "GameFontHighlightSmall", THEME.text)
	row.status:SetPoint("LEFT", 410, 0)
	row.status:SetWidth(220)
	row.remove = Window:CreateButton(row, L.WISH_REMOVE, 80, 20, function()
		local id = row.itemId -- RemoveWish refreshes the rows, read it first
		if id and row.isOwn then
			Inventory:RemoveWish(id)
		end
	end)
	row.remove:SetPoint("RIGHT", -4, 0)
	return row
end

function Tab:CreateWishlistView(frame)
	local view = CreateFrame("Frame", nil, frame)
	view:SetAllPoints(frame)
	view:Hide()
	view.label = Window:CreateText(view, "GameFontNormal", THEME.gold)
	view.label:SetPoint("TOPLEFT", 4, -80)
	view.label:SetText(L.WISH_ADD_LABEL)
	view.input = Window:CreateEditBox(view, 240)
	view.input:SetMaxLetters(255) -- item links are long
	view.input:SetPoint("TOPLEFT", 150, -76)
	view.quantity = Window:CreateEditBox(view, 50)
	view.quantity:SetMaxLetters(5)
	view.quantity:SetPoint("LEFT", view.input, "RIGHT", 6, 0)
	view.quantity:SetText("1")
	local function submit()
		local id, err = Inventory:AddWish(view.input:GetText() or "", view.quantity:GetText())
		if id then
			view.input:SetText("")
			view.input:ClearFocus()
			view.quantity:SetText("1")
			view.message:SetText(L.WISH_ADDED)
		else
			view.message:SetText(err)
		end
	end
	view.input:SetScript("OnEnterPressed", submit)
	view.quantity:SetScript("OnEnterPressed", submit)
	view.add = Window:CreateButton(view, L.WISH_ADD_BUTTON, 170, 22, submit)
	view.add:SetPoint("LEFT", view.quantity, "RIGHT", 6, 0)
	view.message = Window:CreateText(view, "GameFontHighlightSmall", THEME.muted)
	view.message:SetPoint("TOPLEFT", 150, -102)
	view.message:SetWidth(560)
	view.message:SetText(L.WISH_INPUT_HINT)
	view.note = Window:CreateText(view, "GameFontHighlightSmall", THEME.muted)
	view.note:SetPoint("TOPLEFT", 4, -128)
	view.note:SetWidth(700)
	view.note:SetText(L.WISH_NOTE)
	view.rows = {}
	for i = 1, self.MAX_WISH_ROWS do
		view.rows[i] = self:CreateWishRow(view, i)
	end
	view.empty = Window:CreateText(view, "GameFontHighlight", THEME.muted)
	view.empty:SetPoint("TOPLEFT", 4, -164)
	view.empty:SetText(L.WISH_EMPTY)
	hookLinkInsert(view.input)
	return view
end

-- The empty search result's "+ Add to my wishlist": switch over with the
-- search text already in the box.
function Tab:OpenWishlistWith(frame, text)
	self.view = "wishlist"
	self:Refresh(frame)
	if frame.wishView then
		frame.wishView.input:SetText(text or "")
	end
end

function Tab.WishStatus(entry)
	local parts = {}
	if entry.have > 0 then
		local color = entry.enough and "|cff40d040" or "|cffece2cf"
		parts[#parts + 1] = color .. L.WISH_AMONG_FRIENDS:format(entry.have) .. "|r"
	end
	if entry.lootedTonight > 0 then
		parts[#parts + 1] = L.WISH_LOOTED_TONIGHT:format(entry.lootedTonight)
	end
	if #parts == 0 then
		return "|cffb9a988" .. L.WISH_NOBODY_HAS .. "|r"
	end
	return table.concat(parts, " · ")
end

function Tab:FillWishlist(frame, holders)
	local view = frame.wishView
	local entries = Inventory:GetWishEntries(holders)
	for i, row in ipairs(view.rows) do
		local entry = entries[i]
		if entry then
			row.itemId, row.isOwn = entry.id, entry.isSelf
			row.icon:SetTexture(entry.info.icon)
			if row.border.SetBackdropBorderColor then
				row.border:SetBackdropBorderColor(Items.QualityRGB(entry.info.quality))
			end
			row.name:SetText(Items.ColoredName(entry.info) .. " ×" .. entry.wanted)
			row.owner:SetText(entry.isSelf and L.WISH_FOR_YOU or L.WISH_FOR:format(Window:ColorName(entry.owner, entry.class)))
			row.status:SetText(Tab.WishStatus(entry))
			if entry.isSelf then
				row.remove:Show()
			else
				row.remove:Hide() -- a friend's wish is theirs to change
			end
			row:Show()
		else
			row.itemId, row.isOwn = nil, nil
			row:Hide()
		end
	end
	if #entries == 0 then
		view.empty:Show()
	else
		view.empty:Hide()
	end
end

----------------------------------------------------------------------
-- Lifecycle (called from Inventory.lua)
----------------------------------------------------------------------

function Inventory:EnableWishlist()
	ns.Comm:RegisterHandler(self, self.WISH_MSG, self.OnWishMessage)
	ns.Events:Register(self, "CHAT_MSG_LOOT", "OnChatMsgLoot")
end
