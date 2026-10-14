-- Item info for the inventory and wishlist views, and the pure provider
-- that turns everyone's counts into the rows of the Inventory tab.
--
-- Item names and qualities come from the client's item cache. An item seen
-- for the first time (a friend's bag) usually isn't cached yet:
-- GetItemNameByID returns nil until the client has loaded it. Items.Info
-- then asks for it with Item:CreateFromItemID(id):ContinueOnItemLoad and
-- fires LP_ITEM_LOADED when it arrives, so the tab redraws that row.
-- GetItemInfoInstant works without the cache (class, icon, type name).
local _, ns = ...
local L = ns.L

local Inventory = ns:GetModule("Inventory")

local Items = {}
Inventory.Items = Items

-- Filter categories by item class (Enum.ItemClass on Forever: 0 Consumable,
-- 2 Weapon, 3 Gem, 4 Armor, 5 Reagent, 7 Tradegoods).
Items.CATEGORIES = {
	materials = { [3] = true, [5] = true, [7] = true },
	consumables = { [0] = true },
	gear = { [2] = true, [4] = true },
}

-- Quality colors as hex, if the client's ITEM_QUALITY_COLORS isn't there.
local QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff" }

Items.cache = {}   -- itemID -> info
Items.pending = {} -- itemID -> true while loading

local function notSecret(v)
	if ns.IsSecret(v) then
		return nil
	end
	return v
end

-- { id, name (nil while loading), quality, icon, classID, typeName }
function Items.Info(id)
	local info = Items.cache[id]
	if info and info.name then
		return info
	end
	info = info or { id = id }
	local api = C_Item or {}
	if not info.classID and api.GetItemInfoInstant then
		local _, typeName, _, _, icon, classID = api.GetItemInfoInstant(id)
		info.typeName, info.icon, info.classID = notSecret(typeName), notSecret(icon), notSecret(classID)
	end
	local name = api.GetItemNameByID and notSecret(api.GetItemNameByID(id))
	if type(name) == "string" and name ~= "" then
		info.name = name
		info.quality = api.GetItemQualityByID and notSecret(api.GetItemQualityByID(id)) or info.quality
	else
		Items.Load(id)
	end
	Items.cache[id] = info
	return info
end

function Items.Load(id)
	if Items.pending[id] or not (Item and Item.CreateFromItemID) then
		return
	end
	local item = Item:CreateFromItemID(id)
	if not item or (item.IsItemEmpty and item:IsItemEmpty()) then
		return
	end
	Items.pending[id] = true
	item:ContinueOnItemLoad(function()
		Items.pending[id] = nil
		local info = Items.cache[id]
		if info then
			info.name = nil -- read again with the loaded data
		end
		Items.Info(id)
		ns.Events:Fire("LP_ITEM_LOADED", id)
	end)
end

-- "|cffa335eeName|r" in the item's quality color.
function Items.ColoredName(info)
	local hex
	local colors = ITEM_QUALITY_COLORS
	local quality = info.quality
	if quality and colors and colors[quality] and colors[quality].hex then
		hex = colors[quality].hex:gsub("^|c", "")
	elseif quality and QUALITY_HEX[quality] then
		hex = "ff" .. QUALITY_HEX[quality]
	end
	local name = (info.name or L.ITEM_LOADING):gsub("|", "||")
	return hex and ("|c" .. hex .. name .. "|r") or name
end

-- r, g, b of the quality color (for the icon border).
function Items.QualityRGB(quality)
	local hex = QUALITY_HEX[quality or 1] or "ffffff"
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

----------------------------------------------------------------------
-- Rows of the Inventory tab (pure apart from Items.Info)
----------------------------------------------------------------------

-- holders: Inventory:GetHolders(); opts: { search, category, location }.
-- Returns rows sorted by total (highest first, then name), each
-- { id, info, total, holders = { { name, class, isSelf, count, inBank } } },
-- and how many holders have at least one listed item.
function Items.BuildRows(holders, opts)
	opts = opts or {}
	local search = opts.search and opts.search:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	local category = Items.CATEGORIES[opts.category or "all"]
	local location = opts.location or "all"
	local byId = {}
	for _, holder in ipairs(holders) do
		local sources = {}
		if location ~= "bank" and holder.bags then
			sources[#sources + 1] = { map = holder.bags, bank = false }
		end
		if location ~= "bags" and holder.bank then
			sources[#sources + 1] = { map = holder.bank, bank = true }
		end
		for _, source in ipairs(sources) do
			for id, count in pairs(source.map) do
				local row = byId[id]
				if not row then
					row = { id = id, total = 0, holders = {}, byHolder = {} }
					byId[id] = row
				end
				row.total = row.total + count
				local entry = row.byHolder[holder.name]
				if not entry then
					entry = { name = holder.name, class = holder.class, isSelf = holder.isSelf, count = 0, inBank = false }
					row.byHolder[holder.name] = entry
					row.holders[#row.holders + 1] = entry
				end
				entry.count = entry.count + count
				entry.inBank = entry.inBank or source.bank
			end
		end
	end
	local rows, holderSet = {}, {}
	for id, row in pairs(byId) do
		local info = Items.Info(id)
		local keep = not category or (info.classID ~= nil and category[info.classID])
		if keep and search ~= "" then
			keep = info.name ~= nil and info.name:lower():find(search, 1, true) ~= nil
		end
		if keep then
			row.info = info
			row.byHolder = nil
			table.sort(row.holders, function(a, b)
				if a.count ~= b.count then
					return a.count > b.count
				end
				return a.name < b.name
			end)
			for _, entry in ipairs(row.holders) do
				holderSet[entry.name] = true
			end
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		local na, nb = a.info.name or "", b.info.name or ""
		if na ~= nb then
			return na < nb
		end
		return a.id < b.id
	end)
	local holderCount = 0
	for _ in pairs(holderSet) do
		holderCount = holderCount + 1
	end
	return rows, holderCount
end

-- Total of one item among everyone (bags + bank).
function Items.TotalHeld(holders, id)
	local total = 0
	for _, holder in ipairs(holders) do
		total = total + ((holder.bags or {})[id] or 0) + ((holder.bank or {})[id] or 0)
	end
	return total
end
