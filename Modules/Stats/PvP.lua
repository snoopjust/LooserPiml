-- Duels, battlegrounds and honor of the own character. The ranked duel
-- handshake between LooserPiml friends is in Duels.lua; this file parses
-- the result and records it (ranked or not).
--
-- Duels: the result arrives as a system message for every duel nearby, e.g.
-- DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel" and
-- DUEL_WINNER_RETREAT  = "%2$s has fled from %1$s in a duel". Matched with
-- the client's own (localized) format strings; only duels involving the
-- player are recorded. CHAT_MSG_SYSTEM text can be secret during chat
-- lockdown (not where duels happen); then it is skipped.
--
-- Battlegrounds: joined/left from LP_INSTANCE_ENTER/LEAVE (type "pvp"),
-- result from PVP_MATCH_COMPLETE. C_PvP.GetScoreInfo is secret while a match
-- is active, so the own scoreboard row is read only after the match ended
-- and every value is checked.
local _, ns = ...

local Stats = ns:GetModule("Stats")
local Util = ns.Util

local notSecret = ns.PlayerEvents.NotSecret

-- Factions as PVP_MATCH_COMPLETE / PVPScoreInfo report them.
-- TODO(verify in-game): 0 = Horde, 1 = Alliance on Forever.
Stats.FACTION_INDEX = { Horde = 0, Alliance = 1 }

----------------------------------------------------------------------
-- Duels
----------------------------------------------------------------------

function Stats:ParseDuel(text)
	local knockout = DUEL_WINNER_KNOCKOUT and Util.MatchFormat(text, DUEL_WINNER_KNOCKOUT)
	local retreat = not knockout and DUEL_WINNER_RETREAT and Util.MatchFormat(text, DUEL_WINNER_RETREAT)
	local args = knockout or retreat
	if not args or not args[1] or not args[2] then
		return nil
	end
	-- IsPlayer/Resolve also accept "First Surname" and a bare first name
	-- (Forever megaserver, see Roster:Normalize).
	local Roster, Friends = ns.Roster, ns.Friends
	local result, opponent
	if Roster:IsPlayer(args[1]) then
		result, opponent = knockout and "won" or "opponent_fled", Friends:Resolve(args[2])
	elseif Roster:IsPlayer(args[2]) then
		result, opponent = knockout and "lost" or "fled", Friends:Resolve(args[1])
	else
		return nil -- somebody else's duel
	end
	return result, opponent
end

function Stats:OnChatMsgSystem(_, text)
	local result, opponent = self:ParseDuel(text)
	if not result then
		return
	end
	-- Ranked only if both picked Ranked before this result line; the pending
	-- choice ends here either way.
	local ranked, id = self.Duels:TakeResult(opponent)
	if not self:IsCollecting() then
		return
	end
	-- The per-opponent record first: Record() below triggers the stats
	-- message, which carries the ranked duels.
	local record, won = self.Duels:RecordResult(result, opponent, ranked, id)
	self:Record("duel", {
		result = result,
		opponent = opponent,
		-- Only knowable for LooserPiml friends: nobody else is ever asked.
		opponentHasAddon = ns.Friends:HasHandshake(opponent),
		ranked = ranked or nil,
		duelId = id,
	})
	self.Duels:Announce(result, opponent, ranked, record, won)
end

----------------------------------------------------------------------
-- Battlegrounds
----------------------------------------------------------------------

function Stats:OnPvPInstanceEnter(_, info)
	if info.type ~= "pvp" then
		return
	end
	self.battleground = { name = info.name, finished = false }
	self:Record("pvp", { kind = "joined", name = info.name })
end

function Stats:OnPvPInstanceLeave(_, info)
	if info.type ~= "pvp" then
		return
	end
	local bg = self.battleground
	self.battleground = nil
	if bg and not bg.finished then
		self:Record("pvp", { kind = "deserted", name = bg.name })
	end
end

local function myFactionIndex()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return not ns.IsSecret(faction) and Stats.FACTION_INDEX[faction] or nil
end

-- Own scoreboard row after the match, values that are secret are dropped.
function Stats:ReadOwnScore()
	local getScore = C_PvP and C_PvP.GetScoreInfo
	if not getScore then
		return nil
	end
	local me = ns.Roster:GetPlayerName()
	for i = 1, 80 do
		local info = getScore(i)
		if type(info) ~= "table" or ns.IsSecret(info) then
			return nil
		end
		local name = notSecret(info.name)
		if name and ns.Roster:Normalize(name) == me then
			return {
				killingBlows = notSecret(info.killingBlows),
				honorableKills = notSecret(info.honorableKills),
				deaths = notSecret(info.deaths),
				honorGained = notSecret(info.honorGained),
				faction = notSecret(info.faction),
			}
		end
	end
	return nil
end

-- Payload: winner (faction index), duration (seconds).
function Stats:OnPvPMatchComplete(_, winner, duration)
	local bg = self.battleground
	if bg then
		bg.finished = true
	end
	local score = self:ReadOwnScore() or {}
	local mine = score.faction or myFactionIndex()
	winner = notSecret(winner)
	local won
	if type(winner) == "number" and mine ~= nil then
		won = winner == mine
	end
	self:Record("pvp", {
		kind = "finished",
		name = bg and bg.name,
		won = won,
		duration = notSecret(duration),
		killingBlows = score.killingBlows,
		honorableKills = score.honorableKills,
		deaths = score.deaths,
		honorGained = score.honorGained,
	})
end

----------------------------------------------------------------------
-- Honor snapshots
----------------------------------------------------------------------

function Stats:ReadHonor()
	local honor = UnitHonor and notSecret(UnitHonor("player"))
	local level = UnitHonorLevel and notSecret(UnitHonorLevel("player"))
	return type(honor) == "number" and honor or nil, type(level) == "number" and level or nil
end

-- Records a snapshot only when honor or honor level actually changed.
function Stats:OnHonorChanged()
	local honor, level = self:ReadHonor()
	if honor == nil and level == nil then
		return
	end
	local char = self:GetChar()
	local previous = char.honor or {}
	if previous.honor == honor and previous.level == level then
		return
	end
	char.honor = { honor = honor, level = level }
	if previous.honor == nil and previous.level == nil then
		return -- first reading is the baseline, not a change
	end
	self:Record("pvp", { kind = "honor", honor = honor, honorLevel = level })
end

function Stats:EnablePvP()
	ns.Events:Register(self, "CHAT_MSG_SYSTEM", "OnChatMsgSystem")
	ns.Events:Register(self, "PVP_MATCH_COMPLETE", "OnPvPMatchComplete")
	ns.Events:Register(self, "HONOR_XP_UPDATE", "OnHonorChanged")
	ns.Events:Register(self, "PLAYER_PVP_RANK_CHANGED", "OnHonorChanged")
	self:OnHonorChanged()
	self.Duels:Enable()
end
