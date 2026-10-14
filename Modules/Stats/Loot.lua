-- Rare loot, crafting, gathering, chests and skill-ups of the own character.
--
-- Sources:
--   CHAT_MSG_LOOT   "You receive loot: [Item]x2." / "You create: [Item]."
--   CHAT_MSG_SKILL  "Your skill in Mining has increased to 75."
--   LOOT_OPENED     what the loot window belongs to: gathering (herb, ore,
--                   skinning, fishing) or a chest
--
-- The message texts are matched with the client's own GlobalStrings (see
-- Util.MatchFormat), so other client languages work too. Messages about
-- other players' loot use different strings and never match. CHAT_MSG_SKILL
-- text can be secret during chat lockdown; MatchFormat then skips it.
local _, ns = ...

local Stats = ns:GetModule("Stats")
local Util = ns.Util

Stats.RARE_QUALITY = 3 -- Enum.ItemQuality.Rare (blue) and better

-- Gathering casts. Any spell with the same (localized) name counts, so
-- every rank matches. TODO(verify in-game): these IDs exist on Forever
-- and gathering a node really casts a spell of this name.
Stats.GATHER_SPELLS = {
	herb = 2366,     -- Herb Gathering
	mining = 2575,   -- Mining
	skinning = 8613, -- Skinning
}
-- Seconds between the end of a gathering cast and the loot window.
Stats.GATHER_WINDOW = 5

-- Parsing lives in Core/Util (the Inventory module needs it too).
Stats.ItemQuality = Util.ItemQuality
Stats.ParseLootMessage = Util.ParseOwnLoot

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

-- Called by Collectors for the player's successful casts: remembers a
-- gathering cast, so the loot window that follows counts as gathered.
-- secret = the cast happened but its spell was secret (restricted): then
-- the next loot window can't be classified.
function Stats:NoteCast(spellName, secret)
	if secret then
		self.lastCast = { at = GetTime(), secret = true }
		return
	end
	for kind, spellID in pairs(self.GATHER_SPELLS) do
		if spellName and spellName == self:SpellName(spellID) then
			self.lastCast = { at = GetTime(), gather = kind }
			return
		end
	end
end

-- True if the open loot window holds anything that isn't a quest item.
-- Quest objects on the ground (sacks, crates for a quest) are GameObjects
-- too, but they aren't chests. If the slot API is missing, assume a chest.
local function hasNonQuestLoot()
	if not (GetNumLootItems and GetLootSlotInfo) then
		return true
	end
	local count = GetNumLootItems()
	if ns.IsSecret(count) or type(count) ~= "number" then
		return true
	end
	for slot = 1, count do
		local isQuestItem = select(7, GetLootSlotInfo(slot))
		if ns.IsSecret(isQuestItem) or not isQuestItem then
			return true
		end
	end
	return false
end

-- Called from Money.lua's LOOT_OPENED handler. Gathering is told apart by
-- the cast right before the loot window (Herb Gathering, Mining, Skinning;
-- the fishing bobber via IsFishingLoot), because nothing in the loot API
-- says "node". Loot from any other GameObject ("GameObject-..." GUID from
-- GetLootSourceInfo) is a chest: counted as chestsOpened, not as gathered.
-- Chests are only counted for now, the UI doesn't show them yet.
function Stats:OnLootOpened()
	local cast = self.lastCast
	self.lastCast = nil
	local recent = cast and GetTime() - cast.at <= self.GATHER_WINDOW
	local fishing = IsFishingLoot and IsFishingLoot()
	if not ns.IsSecret(fishing) and fishing then
		self:Record("profession", { kind = "gathered", source = "fishing" })
		return
	end
	if recent and cast.gather then
		self:Record("profession", { kind = "gathered", source = cast.gather })
		return
	end
	if recent and cast.secret then
		ns.Log:Debug("Stats: loot source unknown (the cast before it was secret), not counted")
		return
	end
	local guid = GetLootSourceInfo and GetLootSourceInfo(1)
	if ns.IsSecret(guid) or type(guid) ~= "string" then
		return
	end
	if guid:match("^GameObject%-") and hasNonQuestLoot() then
		self:Count("chestsOpened", 1)
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
