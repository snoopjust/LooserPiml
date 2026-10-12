-- Game events -> Stats:Record() for deaths, level-ups, quests, instances,
-- boss encounters, travel and "fun" counters. Money, loot/professions and
-- PvP have their own files.
--
-- Rules for every collector: each client records only its own character;
-- anything secret or missing on this client is skipped (debug log line),
-- never worked around; hooks are hooksecurefunc post-hooks only, which run
-- after Blizzard's function and can't change or block it.
local _, ns = ...

local Stats = ns:GetModule("Stats")

local notSecret = ns.PlayerEvents.NotSecret

Stats.HEARTHSTONE_SPELL = 8690 -- TODO(verify in-game): same spell ID on Forever
Stats.FOOD_SPELL = 433         -- any spell named like this one is "eating"  TODO(verify in-game)
Stats.DRINK_SPELL = 430        -- any spell named like this one is "drinking" TODO(verify in-game)

-- Installs a post-hook once per session (hooks can't be removed, so they
-- check IsCollecting themselves). Returns false if the function is missing.
local installedHooks = {}
function Stats:PostHook(name, fn)
	if installedHooks[name] then
		return true
	end
	if type(_G[name]) ~= "function" then
		ns.Log:Debug("Stats: %s not available on this client, related stats are not recorded", name)
		return false
	end
	hooksecurefunc(name, function(...)
		if self:IsCollecting() then
			ns.SafeCall(fn, ...)
		end
	end)
	installedHooks[name] = true
	return true
end

function Stats:EnableCollectors()
	-- From Core/PlayerEvents (also used by the Ticker)
	ns.Events:Register(self, "LP_PLAYER_DEAD", "OnPlayerDead")
	ns.Events:Register(self, "LP_PLAYER_LEVEL_UP", "OnPlayerLevelUp")
	ns.Events:Register(self, "LP_INSTANCE_ENTER", "OnInstanceEnter")
	ns.Events:Register(self, "LP_INSTANCE_LEAVE", "OnInstanceLeave")
	-- The raw game event, not LP_ENCOUNTER_END: test mode fires that one for
	-- simulated bosses, which must never end up in recorded stats.
	ns.Events:Register(self, "ENCOUNTER_END", "OnEncounterEnd")
	ns.Events:Register(self, "QUEST_TURNED_IN", "OnQuestTurnedIn")
	ns.Events:Register(self, "ZONE_CHANGED", "OnZoneChanged")
	ns.Events:Register(self, "ZONE_CHANGED_INDOORS", "OnZoneChanged")
	ns.Events:Register(self, "ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
	ns.Events:Register(self, "UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
	self:PostHook("TakeTaxiNode", function(index)
		self:OnFlightTaken(index)
	end)
	self:PostHook("JumpOrAscendStart", function()
		self:OnJump()
	end)
	for _, enable in ipairs({ "EnableMoney", "EnableLoot", "EnablePvP", "EnableSync" }) do
		if self[enable] then
			self[enable](self)
		end
	end
	self:OnZoneChanged() -- the zone we log in to counts as visited
end

----------------------------------------------------------------------
-- Death, level, instance, encounter, quests
----------------------------------------------------------------------

function Stats:OnPlayerDead(_, info)
	self:Record("death", {
		drowned = info.drowned or nil,
		duringEncounter = info.duringEncounter or nil,
		itype = info.instanceType,
	})
end

-- One registration per event and owner, so the battleground bookkeeping in
-- PvP.lua is called from here instead of registering a second handler.
function Stats:OnInstanceEnter(event, info)
	self:Record("instance", { action = "enter", itype = info.type, name = info.name, id = info.id })
	if self.OnPvPInstanceEnter then
		self:OnPvPInstanceEnter(event, info)
	end
end

function Stats:OnInstanceLeave(event, info)
	self:Record("instance", { action = "leave", itype = info.type, name = info.name, id = info.id })
	if self.OnPvPInstanceLeave then
		self:OnPvPInstanceLeave(event, info)
	end
end

-- Payload: encounterID, encounterName, difficultyID, groupSize, success (1/0).
function Stats:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
	if ns.IsSecret(success) then
		ns.Log:Debug("Stats: encounter result is secret, not recorded")
		return
	end
	self:Record("encounter", {
		id = notSecret(encounterID),
		name = notSecret(encounterName),
		difficulty = notSecret(difficultyID),
		size = notSecret(groupSize),
		success = success == 1,
	})
end

-- Payload: questID, xpReward, moneyReward (copper). The money itself also
-- arrives as a PLAYER_MONEY change; the hint lets Money.lua call it "quest".
function Stats:OnQuestTurnedIn(_, questID, xpReward, moneyReward)
	self:Record("quest_done", {
		id = notSecret(questID),
		xp = notSecret(xpReward),
		money = notSecret(moneyReward),
	})
	self:SetMoneyHint("quest")
end

----------------------------------------------------------------------
-- Travel
----------------------------------------------------------------------

-- "Discovered" means: first time this character was seen in this
-- zone/subzone since LooserPiml was installed. The game's own exploration
-- state isn't readable for every subzone, so this is our own bookkeeping.
function Stats:OnZoneChanged()
	local zone = notSecret(GetRealZoneText and GetRealZoneText())
	local subzone = notSecret(GetSubZoneText and GetSubZoneText())
	if type(zone) ~= "string" or zone == "" then
		return
	end
	if subzone == "" then
		subzone = nil
	end
	local key = zone .. "/" .. (subzone or "")
	local zones = self:GetChar().zones
	if zones[key] or not self:IsCollecting() then
		return
	end
	zones[key] = true
	self:Record("travel", { kind = "zone_new", zone = zone, subzone = subzone })
end

-- TakeTaxiNode(index) is what the flight map calls when you pick a
-- destination; the post-hook only reads the destination name.
function Stats:OnFlightTaken(index)
	local destination = TaxiNodeName and notSecret(TaxiNodeName(index))
	self:Record("travel", { kind = "flight", to = destination })
	self:SetMoneyHint("flight")
end

-- Payload: unitTarget, castGUID, spellID. Can be secret while spell casts
-- are restricted (combat); then nothing is counted.
function Stats:OnSpellcastSucceeded(_, unit, _, spellID)
	if unit ~= "player" then
		return
	end
	if ns.IsSecret(spellID) then
		self:NoteCast(nil, true) -- Loot.lua: the next loot window can't be classified
		return
	end
	if type(spellID) ~= "number" then
		return
	end
	if spellID == self.HEARTHSTONE_SPELL then
		self:Record("travel", { kind = "hearth" })
		return
	end
	local name = self:SpellName(spellID)
	self:NoteCast(name)
	if name and name == self:SpellName(self.FOOD_SPELL) then
		self:Count("food", 1)
	elseif name and name == self:SpellName(self.DRINK_SPELL) then
		self:Count("drink", 1)
	end
end

-- Localized spell name, so "Food"/"Drink" work in every client language.
function Stats:SpellName(spellID)
	local getName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
	if not getName then
		return nil
	end
	local name = getName(spellID)
	if ns.IsSecret(name) or type(name) ~= "string" then
		return nil
	end
	return name
end

----------------------------------------------------------------------
-- Fun
----------------------------------------------------------------------

-- JumpOrAscendStart is protected (only secure code may call it). We neither
-- call nor replace it: hooksecurefunc runs our counter after Blizzard's
-- code. It also fires for "ascend" while swimming/flying and for presses in
-- mid-air, which are not jumps. TODO(verify in-game): IsFalling() is still
-- false right after a ground jump starts.
local function isTrue(value)
	return not ns.IsSecret(value) and value and true or false
end

function Stats:OnJump()
	if isTrue(IsSwimming and IsSwimming()) or isTrue(IsFlying and IsFlying()) or isTrue(IsFalling and IsFalling()) then
		return
	end
	self:Count("jumps", 1)
end
