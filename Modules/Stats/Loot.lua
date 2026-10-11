-- Rare loot, crafting, gathering and skill-ups of the own character.
--
-- Sources:
--   CHAT_MSG_LOOT   "You receive loot: [Item]x2." / "You create: [Item]."
--   CHAT_MSG_SKILL  "Your skill in Mining has increased to 75."
--   LOOT_OPENED     whether the loot window belongs to a gathering node
--
-- The message texts are matched with the client's own GlobalStrings (see
-- Util.MatchFormat), so other client languages work too. Messages about
-- other players' loot use different strings and never match. CHAT_MSG_SKILL
-- text can be secret during chat lockdown; MatchFormat then skips it.
local _, ns = ...

local Stats = ns:GetModule("Stats")
local Util = ns.Util

Stats.RARE_QUALITY = 3 -- Enum.ItemQuality.Rare (blue) and better

-- Own-loot GlobalStrings, "...MULTIPLE" first: the single form would also
-- match "[Item]x2." and swallow the count.
Stats.LOOT_FORMATS = {
	{ name = "LOOT_ITEM_SELF_MULTIPLE", kind = "loot", multiple = true },
	{ name = "LOOT_ITEM_SELF", kind = "loot" },
	{ name = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", kind = "loot", multiple = true },
	{ name = "LOOT_ITEM_PUSHED_SELF", kind = "loot" },
	{ name = "LOOT_ITEM_CREATED_SELF_MULTIPLE", kind = "created", multiple = true },
	{ name = "LOOT_ITEM_CREATED_SELF", kind = "created" },
}

-- Classic item link colors, used only if the item API can't tell yet.
local LINK_COLORS = {
	ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6,
}

-- Quality of an item link: the item API first (nil while the item isn't
-- cached yet), then the quality marker or color embedded in the link.
function Stats.ItemQuality(link)
	if type(link) ~= "string" then
		return nil
	end
	local getQuality = C_Item and C_Item.GetItemQualityByID
	if getQuality then
		local quality = getQuality(link)
		if type(quality) == "number" and not ns.IsSecret(quality) then
			return quality
		end
	end
	local marker = link:match("|cnIQ(%d+):")
	if marker then
		return tonumber(marker)
	end
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	return color and LINK_COLORS[color:lower()] or nil
end

-- Parses an own loot/create message. Returns kind, link, count or nil.
function Stats.ParseLootMessage(text)
	for _, format in ipairs(Stats.LOOT_FORMATS) do
		local fmt = _G[format.name]
		local args = fmt and Util.MatchFormat(text, fmt)
		if args then
			local count = format.multiple and Util.ToNumber(args[2]) or 1
			return format.kind, args[1], count
		end
	end
	return nil
end

function Stats:OnChatMsgLoot(_, text)
	local kind, link, count = Stats.ParseLootMessage(text)
	if not kind then
		return
	end
	if kind == "created" then
		self:Record("profession", { kind = "crafted", item = link, count = count })
		return
	end
	local quality = Stats.ItemQuality(link)
	if quality and quality >= self.RARE_QUALITY then
		self:Record("loot_rare", { item = link, quality = quality, count = count })
	elseif not quality then
		ns.Log:Debug("Stats: quality of %s unknown, not recorded as rare loot", tostring(link))
	end
end

-- Called from Money.lua's LOOT_OPENED handler. GetLootSourceInfo(slot)
-- returns the GUID of what is being looted; "GameObject-..." means a node
-- (herb, ore) or a chest, "Creature-..." a mob. Fishing loot is counted
-- separately because the bobber is a GameObject too.
function Stats:OnLootOpened()
	if not GetLootSourceInfo then
		return
	end
	local guid = GetLootSourceInfo(1)
	if ns.IsSecret(guid) or type(guid) ~= "string" then
		return
	end
	local fishing = IsFishingLoot and IsFishingLoot()
	if not ns.IsSecret(fishing) and fishing then
		self:Record("profession", { kind = "gathered", source = "fishing" })
	elseif guid:match("^GameObject%-") then
		self:Record("profession", { kind = "gathered", source = "object" })
	end
end

-- Profession names of this character, if the client can tell
-- (GetProfessions/GetProfessionInfo; TODO(verify in-game) on Forever).
function Stats:ProfessionNames()
	local names = {}
	if not (GetProfessions and GetProfessionInfo) then
		return nil
	end
	for _, index in ipairs({ GetProfessions() }) do
		if type(index) == "number" then
			local name = GetProfessionInfo(index)
			if type(name) == "string" and not ns.IsSecret(name) then
				names[name] = true
			end
		end
	end
	return names
end

function Stats:OnChatMsgSkill(_, text)
	local args = SKILL_RANK_UP and Util.MatchFormat(text, SKILL_RANK_UP)
	if not args then
		return
	end
	local skill, rank = args[1], Util.ToNumber(args[2])
	local professions = self:ProfessionNames()
	local isProfession -- nil = the client can't tell
	if professions then
		isProfession = professions[skill] == true
	end
	self:Record("profession", { kind = "skillup", skill = skill, rank = rank, profession = isProfession })
end

function Stats:EnableLoot()
	ns.Events:Register(self, "CHAT_MSG_LOOT", "OnChatMsgLoot")
	ns.Events:Register(self, "CHAT_MSG_SKILL", "OnChatMsgSkill")
end
