-- The "Inventory" tab: Friends' inventory. Frame code only; the rows come
-- from Items.BuildRows (pure), the data from Inventory:GetHolders.
--
-- Layout (content area about 736 x 440):
--   title + subtitle                         [Items] [Wishlists]
--   gold bar: one chip per friend who shares gold, plus a total
--   Items view: search, category + location filters, count line,
--               item rows (left), "Last updated" column (right)
--   Wishlists view: Wishlist.lua
-- There is deliberately no button to ask a friend for an item: LooserPiml
-- never sends whispers or chat messages on the player's behalf.
local _, ns = ...
local L = ns.L

local Inventory = ns:GetModule("Inventory")
local Window = ns.Window
local Items = Inventory.Items
local THEME = Window.THEME

local Tab = {}
Inventory.InventoryTab = Tab

Tab.MAX_ROWS = 8
Tab.ROW_HEIGHT = 28
Tab.MAX_CHIPS = 3       -- holder chips per row ("+N" after that)
Tab.MAX_GOLD_CHIPS = 6
Tab.MAX_UPDATED = 8     -- friends in the "Last updated" column
Tab.ROWS_TOP = -158
Tab.RIGHT_X = 548

Tab.view = "items"
Tab.search = ""
Tab.category = "all"
Tab.location = "all"
Tab.page = 1

Tab.CATEGORIES = {
	{ id = "all", label = L.INV_FILTER_ALL },
	{ id = "materials", label = L.INV_FILTER_MATERIALS },
	{ id = "consumables", label = L.INV_FILTER_CONSUMABLES },
	{ id = "gear", label = L.INV_FILTER_GEAR },
}
Tab.LOCATIONS = {
	{ id = "all", label = L.INV_FILTER_BAGS_BANK },
	{ id = "bags", label = L.INV_FILTER_BAGS },
	{ id = "bank", label = L.INV_FILTER_BANK },
}

local function chipText(name, class, extra)
	return Window:ColorName(name, class) .. (extra and (" " .. extra) or "")
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function Tab:CreateChip(parent, width)
	local chip = Window:CreatePanel(parent)
	chip:SetSize(width, 20)
	chip.text = Window:CreateText(chip, "GameFontHighlightSmall", THEME.text, "CENTER")
	chip.text:SetPoint("CENTER")
	chip.text:SetWidth(width - 6)
	return chip
end

function Tab:CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(530, self.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, self.ROWS_TOP - (index - 1) * self.ROW_HEIGHT)
	-- Icon with a quality-colored border.
	row.border = Window:CreatePanel(row)
	row.border:SetSize(24, 24)
	row.border:SetPoint("LEFT", 2, 0)
	row.icon = row.border:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 2, -2)
	row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	row.name = Window:CreateText(row, "GameFontHighlight", THEME.text)
	row.name:SetPoint("LEFT", 32, 5)
	row.name:SetWidth(150)
	row.category = Window:CreateText(row, "GameFontHighlightSmall", THEME.muted)
	row.category:SetPoint("LEFT", 32, -7)
	row.category:SetWidth(150)
	row.total = Window:CreateText(row, "GameFontNormal", THEME.gold, "RIGHT")
	row.total:SetPoint("LEFT", 186, 0)
	row.total:SetWidth(44)
	row.chips = {}
	for i = 1, self.MAX_CHIPS do
		local chip = self:CreateChip(row, 92)
		chip:SetPoint("LEFT", 238 + (i - 1) * 96, 0)
		row.chips[i] = chip
	end
	return row
end

function Tab:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.title = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.title:SetPoint("TOPLEFT", 4, -4)
	frame.title:SetText(L.INV_TITLE)
	frame.subtitle = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.subtitle:SetPoint("TOPLEFT", 4, -24)
	frame.subtitle:SetText(L.INV_SUBTITLE)

	frame.viewButtons = {}
	for i, view in ipairs({ { "items", L.INV_VIEW_ITEMS }, { "wishlist", L.INV_VIEW_WISHLIST } }) do
		local button = Window:CreateButton(frame, view[2], 96, 22, function()
			self.view = view[1]
			self:Refresh(frame)
		end)
		button:SetPoint("TOPRIGHT", -(2 - i) * 100, -2)
		button.viewId = view[1]
		frame.viewButtons[i] = button
	end

	-- Gold bar
	frame.goldChips = {}
	for i = 1, self.MAX_GOLD_CHIPS + 1 do
		local chip = self:CreateChip(frame, 100)
		chip:SetPoint("TOPLEFT", (i - 1) * 104, -46)
		frame.goldChips[i] = chip
	end

	-- Items view
	local items = CreateFrame("Frame", nil, frame)
	items:SetAllPoints(frame)
	frame.itemsView = items
	items.search = Window:CreateEditBox(items, 180)
	items.search:SetPoint("TOPLEFT", 4, -76)
	items.search:SetScript("OnTextChanged", function(box)
		self.search = box:GetText() or ""
		self.page = 1
		self:Refresh(frame)
	end)
	items.searchHint = Window:CreateText(items, "GameFontHighlightSmall", THEME.muted)
	items.searchHint:SetPoint("LEFT", items.search, "LEFT", 8, 0)
	items.searchHint:SetText(L.INV_SEARCH_HINT)
	items.categoryButtons = {}
	for i, entry in ipairs(self.CATEGORIES) do
		local button = Window:CreateButton(items, entry.label, 86, 22, function()
			self.category = entry.id
			self.page = 1
			self:Refresh(frame)
		end)
		button:SetPoint("TOPLEFT", 192 + (i - 1) * 90, -76)
		button.filterId = entry.id
		items.categoryButtons[i] = button
	end
	items.locationButtons = {}
	for i, entry in ipairs(self.LOCATIONS) do
		local button = Window:CreateButton(items, entry.label, 96, 22, function()
			self.location = entry.id
			self.page = 1
			self:Refresh(frame)
		end)
		button:SetPoint("TOPLEFT", 192 + (i - 1) * 100, -102)
		button.filterId = entry.id
		items.locationButtons[i] = button
	end
	items.count = Window:CreateText(items, "GameFontHighlightSmall", THEME.muted)
	items.count:SetPoint("TOPLEFT", 4, -134)
	items.rows = {}
	for i = 1, self.MAX_ROWS do
		items.rows[i] = self:CreateRow(items, i)
	end
	items.empty = Window:CreateText(items, "GameFontHighlight", THEME.muted)
	items.empty:SetPoint("TOPLEFT", 4, self.ROWS_TOP - 6)
	items.empty:SetWidth(520)
	items.emptyAdd = Window:CreateButton(items, L.WISH_ADD_BUTTON, 170, 22, function()
		if self.OpenWishlistWith then
			self:OpenWishlistWith(frame, self.search)
		end
	end)
	items.emptyAdd:SetPoint("TOPLEFT", 4, self.ROWS_TOP - 50)
	items.prev = Window:CreateButton(items, "<", 28, 20, function()
		self.page = math.max(1, self.page - 1)
		self:Refresh(frame)
	end)
	items.prev:SetPoint("TOPLEFT", 4, self.ROWS_TOP - self.MAX_ROWS * self.ROW_HEIGHT - 4)
	items.next = Window:CreateButton(items, ">", 28, 20, function()
		self.page = self.page + 1
		self:Refresh(frame)
	end)
	items.next:SetPoint("LEFT", items.prev, "RIGHT", 4, 0)
	items.pageText = Window:CreateText(items, "GameFontHighlightSmall", THEME.muted)
	items.pageText:SetPoint("LEFT", items.next, "RIGHT", 8, 0)

	-- Right column: last updated per friend
	items.updatedHeader = Window:CreateText(items, "GameFontNormal", THEME.gold)
	items.updatedHeader:SetPoint("TOPLEFT", self.RIGHT_X, -134)
	items.updatedHeader:SetText(L.INV_LAST_UPDATED)
	items.updated = {}
	for i = 1, self.MAX_UPDATED do
		local line = Window:CreateText(items, "GameFontHighlightSmall", THEME.text)
		line:SetPoint("TOPLEFT", self.RIGHT_X, -134 - i * 30)
		line:SetWidth(188)
		items.updated[i] = line
	end
	items.updatedNote = Window:CreateText(items, "GameFontHighlightSmall", THEME.muted)
	items.updatedNote:SetPoint("TOPLEFT", self.RIGHT_X, -134 - (self.MAX_UPDATED + 1) * 30)
	items.updatedNote:SetWidth(188)
	items.updatedNote:SetText(L.INV_BANK_NOTE)

	if self.CreateWishlistView then
		frame.wishView = self:CreateWishlistView(frame)
	end
	return frame
end

----------------------------------------------------------------------
-- Filling
----------------------------------------------------------------------

-- "bags now · bank 3 days ago" / "offline · last seen yesterday 23:10"
function Tab.UpdatedText(holder, now)
	local Util = ns.Util
	if not holder.online then
		return L.INV_UPDATED_OFFLINE:format(Util.FormatWhen(holder.seen, now) or L.INV_NEVER)
	end
	if not holder.bags then
		return L.INV_UPDATED_NOT_SHARED
	end
	local bank = holder.bankAt and Util.FormatAgo(holder.bankAt, now) or L.INV_NEVER
	return L.INV_UPDATED_ONLINE:format(bank)
end

function Tab:FillGold(frame, holders)
	local Util = ns.Util
	local chips, total, i = frame.goldChips, 0, 0
	holders = { unpack(holders) } -- sorted copy, richest first
	table.sort(holders, function(a, b)
		return (a.gold or -1) > (b.gold or -1)
	end)
	for _, holder in ipairs(holders) do
		if holder.gold and i < self.MAX_GOLD_CHIPS then
			i = i + 1
			total = total + holder.gold
			local stale = not holder.online and Util.FormatAgo(holder.seen) or nil
			local text = chipText(holder.name, holder.class, Util.FormatMoney(holder.gold))
			if stale then
				text = text .. " |cff999999(" .. stale .. ")|r"
			end
			chips[i].text:SetText(text)
			chips[i]:Show()
		elseif holder.gold then
			total = total + holder.gold
		end
	end
	if i > 0 then
		i = i + 1
		chips[i].text:SetText(L.INV_GOLD_TOTAL:format(Util.FormatMoney(total)))
		chips[i]:Show()
	end
	for j = i + 1, #chips do
		chips[j]:Hide()
	end
	frame.goldTotal = total
end

function Tab:FillItems(frame, holders)
	local items = frame.itemsView
	if self.search ~= "" then
		items.searchHint:Hide()
	else
		items.searchHint:Show()
	end
	for _, button in ipairs(items.categoryButtons) do
		button:SetSelected(button.filterId == self.category)
	end
	for _, button in ipairs(items.locationButtons) do
		button:SetSelected(button.filterId == self.location)
	end
	local rows, holderCount = Items.BuildRows(holders, { search = self.search, category = self.category, location = self.location })
	frame.lastRows = rows
	items.count:SetText(L.INV_COUNT:format(#rows, holderCount))
	local pages = math.max(1, math.ceil(#rows / self.MAX_ROWS))
	self.page = math.min(self.page, pages)
	local first = (self.page - 1) * self.MAX_ROWS
	for i, widget in ipairs(items.rows) do
		local row = rows[first + i]
		if row then
			local info = row.info
			widget.itemId = row.id
			widget.icon:SetTexture(info.icon)
			if widget.border.SetBackdropBorderColor then
				widget.border:SetBackdropBorderColor(Items.QualityRGB(info.quality))
			end
			widget.name:SetText(Items.ColoredName(info))
			widget.category:SetText(info.typeName or "")
			widget.total:SetText(tostring(row.total))
			for c, chip in ipairs(widget.chips) do
				local entry = row.holders[c]
				if entry and c == self.MAX_CHIPS and #row.holders > self.MAX_CHIPS then
					chip.text:SetText(L.INV_MORE_HOLDERS:format(#row.holders - self.MAX_CHIPS + 1))
					chip:Show()
				elseif entry then
					local extra = tostring(entry.count)
					if entry.inBank then
						extra = extra .. " |cff999999" .. L.INV_BANK_TAG .. "|r"
					end
					chip.text:SetText(chipText(entry.name, entry.class, extra))
					chip:Show()
				else
					chip:Hide()
				end
			end
			widget:Show()
		else
			widget.itemId = nil
			widget:Hide()
		end
	end
	if #rows == 0 then
		items.empty:SetText(self.search ~= "" and L.INV_EMPTY_SEARCH or L.INV_EMPTY)
		items.empty:Show()
		if self.search ~= "" then
			items.emptyAdd:Show()
		else
			items.emptyAdd:Hide()
		end
	else
		items.empty:Hide()
		items.emptyAdd:Hide()
	end
	if pages > 1 then
		items.prev:Show()
		items.next:Show()
		items.pageText:SetText(L.INV_PAGE:format(self.page, pages))
		items.pageText:Show()
	else
		items.prev:Hide()
		items.next:Hide()
		items.pageText:Hide()
	end

	local now = time()
	local others = {}
	for _, holder in ipairs(holders) do
		if not holder.isSelf then
			others[#others + 1] = holder
		end
	end
	table.sort(others, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		return a.name < b.name
	end)
	for i, line in ipairs(items.updated) do
		local holder = others[i]
		if holder then
			line:SetText(Window:ColorName(holder.name, holder.class) .. "\n|cffb9a988" .. Tab.UpdatedText(holder, now) .. "|r")
			line:Show()
		else
			line:SetText(i == 1 and L.INV_NO_FRIENDS or "")
			line:Show()
		end
	end
end

function Tab:Refresh(frame)
	local holders = Inventory:GetHolders()
	for _, button in ipairs(frame.viewButtons) do
		button:SetSelected(button.viewId == self.view)
	end
	self:FillGold(frame, holders)
	if self.view == "wishlist" and frame.wishView then
		frame.itemsView:Hide()
		frame.wishView:Show()
		self:FillWishlist(frame, holders)
	else
		self.view = "items"
		if frame.wishView then
			frame.wishView:Hide()
		end
		frame.itemsView:Show()
		self:FillItems(frame, holders)
	end
end

function Inventory:RegisterUI()
	Window:RegisterTab({
		id = "inventory",
		title = L.TAB_INVENTORY,
		order = 20,
		create = function(parent)
			return Tab:Create(parent)
		end,
		refresh = function(frame)
			Tab:Refresh(frame)
		end,
	})
end
