-- The Profiles tab: one player in depth. Left: me and my LooserPiml
-- friends (connected or cached) with their level. Right: everything
-- LooserPiml recorded for the selected player, from the synced all-time
-- aggregates plus a few profile extras (professions, favourite zone,
-- evenings played) that travel with the STATS message.
--
-- Profiles.Sections is pure: it maps a profile to labelled values and
-- shows "—" for anything without data (nothing recorded yet, or a friend
-- on an older LooserPiml that doesn't send that field).
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")
local Window = ns.Window
local THEME = Window.THEME

local Profiles = {}
Stats.Profiles = Profiles

Profiles.DASH = "—"
Profiles.MAX_PROFESSIONS = 6

----------------------------------------------------------------------
-- Profile extras (own character), sent with STATS
----------------------------------------------------------------------

-- { { n = name, r = skill } } from GetProfessions/GetProfessionInfo, or nil.
-- TODO(verify in-game): both exist on Forever (shared with Loot.lua).
function Stats:ProfessionList()
	if not (GetProfessions and GetProfessionInfo) then
		return nil
	end
	local list = {}
	for _, index in ipairs({ GetProfessions() }) do
		if type(index) == "number" and #list < Profiles.MAX_PROFESSIONS then
			local name, _, rank = GetProfessionInfo(index)
			if type(name) == "string" and not ns.IsSecret(name) then
				list[#list + 1] = { n = name, r = (type(rank) == "number" and not ns.IsSecret(rank)) and rank or nil }
			end
		end
	end
	return #list > 0 and list or nil
end

-- The zone that shows up most often in the own event log (every event
-- carries its zone). Cached until the stats change.
function Stats:FavouriteZone()
	if self.favCache and self.favCacheFor == self.cache then
		return self.favCache
	end
	local counts, best, bestCount = {}, nil, 0
	for _, e in ipairs(self:GetChar().log) do
		local zone = e.zone
		if type(zone) == "string" and zone ~= "" then
			counts[zone] = (counts[zone] or 0) + 1
			if counts[zone] > bestCount or (counts[zone] == bestCount and zone < best) then
				best, bestCount = zone, counts[zone]
			end
		end
	end
	self.favCache, self.favCacheFor = best, self.cache
	return best
end

-- Gaming days with anything recorded (log events and rolled-up days).
function Stats:EveningsPlayed()
	local char = self:GetChar()
	local days, count = {}, 0
	for day in pairs(char.buckets) do
		if not days[day] then
			days[day], count = true, count + 1
		end
	end
	for _, e in ipairs(char.log) do
		local day = self.Model.DayKey(e.t)
		if not days[day] then
			days[day], count = true, count + 1
		end
	end
	return count > 0 and count or nil
end

-- Untrusted extras from a friend's STATS message -> prof, fav, eve.
function Stats.CleanProfileExtras(data)
	local prof
	if type(data.prof) == "table" then
		prof = {}
		for _, p in ipairs(data.prof) do
			if #prof >= Profiles.MAX_PROFESSIONS then
				break
			end
			if type(p) == "table" and type(p.n) == "string" and p.n ~= "" then
				local rank = type(p.r) == "number" and p.r == p.r and p.r >= 0 and p.r <= 1000 and math.floor(p.r) or nil
				prof[#prof + 1] = { n = p.n:sub(1, 40):gsub("|", "||"), r = rank }
			end
		end
		if #prof == 0 then
			prof = nil
		end
	end
	local fav = type(data.fav) == "string" and data.fav ~= "" and data.fav:sub(1, 64):gsub("|", "||") or nil
	local eve = type(data.eve) == "number" and data.eve == data.eve and data.eve >= 0 and data.eve <= 100000 and math.floor(data.eve) or nil
	return prof, fav, eve
end

----------------------------------------------------------------------
-- Profiles
----------------------------------------------------------------------

-- Me first, then listed friends who answered a handshake (and sample
-- friends in test mode): { name, class, level, online, isSelf, agg, gold,
-- prof, fav, eve }
function Stats:GetProfiles()
	local list = {}
	for _, p in ipairs(self:GetParticipants("all")) do
		local profile = { name = p.name, class = p.class, online = p.online, isSelf = p.isSelf, agg = p.agg, gold = p.gold }
		if p.isSelf then
			profile.level = ns.PlayerEvents:GetLevel()
			profile.prof, profile.fav, profile.eve = self:ProfessionList(), self:FavouriteZone(), self:EveningsPlayed()
		else
			local cached = (p.fake and self.fakeFriends or self.db.friendStats)[p.name] or {}
			profile.level, profile.prof, profile.fav, profile.eve = cached.level, cached.prof, cached.fav, cached.eve
		end
		list[#list + 1] = profile
	end
	table.sort(list, function(a, b)
		if a.isSelf ~= b.isSelf then
			return a.isSelf == true
		end
		return a.name < b.name
	end)
	return list
end

local function num(v)
	if v == nil then
		return Profiles.DASH
	end
	return tostring(math.floor(v + 0.5))
end

local function money(v)
	return v and ns.Util.FormatMoney(v) or Profiles.DASH
end

local function duration(v)
	return v and ns.Util.FormatDuration(v) or Profiles.DASH
end

local function pair(a, b)
	if a == nil and b == nil then
		return Profiles.DASH
	end
	return num(a or 0) .. " / " .. num(b or 0)
end

-- { { title, rows = { { label, value } } } } for a profile.
function Profiles.Sections(profile)
	local agg = profile.agg or Stats.Model.Empty()
	local n = agg.n or {}
	local moneyIn, moneyOut = agg.moneyIn or {}, agg.moneyOut or {}
	local honorLevel = agg.last and agg.last.honorLevel and agg.last.honorLevel.v
	local professions = Profiles.DASH
	if profile.prof then
		local parts = {}
		for _, p in ipairs(profile.prof) do
			parts[#parts + 1] = p.r and (p.n .. " " .. p.r) or p.n
		end
		professions = table.concat(parts, ", ")
	end
	return {
		{ title = L.PROFILE_PROGRESS, rows = {
			{ L.PROFILE_LEVEL, num(profile.level) },
			{ L.PROFILE_PLAYED, duration(n.playedSeconds) },
			{ L.PROFILE_AVG_LEVEL, duration(Stats.Model.AverageLevelTime(agg)) },
			{ L.PROFILE_QUESTS, num(n.quests) },
		} },
		{ title = L.PROFILE_DEATHS, rows = {
			{ L.PROFILE_DEATHS_TOTAL, num(n.deaths) },
			{ L.PROFILE_DROWNED, num(n.drowned) },
			{ L.PROFILE_BOSS_DEATHS, num(n.deathsInEncounter) },
			{ L.PROFILE_FIRST_DEATHS, num(n.firstDeaths) },
		} },
		{ title = L.PROFILE_LOOT, rows = {
			{ L.PROFILE_GOLD, money(profile.gold) },
			{ L.PROFILE_EARNED_AH, money(moneyIn.ah_mail) },
			{ L.PROFILE_EARNED_VENDOR, money(moneyIn.vendor_sell) },
			{ L.PROFILE_REPAIRS, money(moneyOut.repair) },
			{ L.PROFILE_RARE_EPIC, pair(n.lootRare, n.lootEpic) },
		} },
		{ title = L.PROFILE_PROFESSIONS, rows = {
			{ L.PROFILE_PROFESSION_LIST, professions },
			{ L.PROFILE_SKILLUPS, num(n.skillUps) },
			{ L.PROFILE_CRAFTED, num(n.crafted) },
			{ L.PROFILE_GATHERED, num(n.gathered) },
		} },
		{ title = L.PROFILE_TRAVEL, rows = {
			{ L.PROFILE_ZONES, num(n.zonesDiscovered) },
			{ L.PROFILE_FLIGHTS, num(n.flights) },
			{ L.PROFILE_HEARTHS, num(n.hearths) },
			{ L.PROFILE_FAV_ZONE, profile.fav or Profiles.DASH },
		} },
		{ title = L.PROFILE_PVP, rows = {
			{ L.PROFILE_RANK, num(honorLevel) },
			{ L.PROFILE_BG_WON, num(n.bgWon) },
			{ L.PROFILE_RANKED_DUELS, pair(n.rankedWon, n.rankedLost) },
			{ L.PROFILE_DUELS, pair(n.duelsWon, n.duelsLost) },
		} },
		{ title = L.PROFILE_SOCIAL, rows = {
			{ L.PROFILE_JUMPS, num(n.jumps) },
			{ L.PROFILE_FOOD, num(n.food) },
			{ L.PROFILE_GROUPED, duration(n.groupSeconds) },
			{ L.PROFILE_EVENINGS, num(profile.eve) },
		} },
	}
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------

local Tab = {}
Stats.ProfilesTab = Tab

Tab.MAX_PLAYERS = 12
Tab.MAX_SECTION_ROWS = 5
Tab.selected = nil

function Tab:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.subtitle = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.subtitle:SetPoint("TOPLEFT", 4, -6)
	frame.subtitle:SetText(L.PROFILE_SUBTITLE)
	frame.players = {}
	for i = 1, self.MAX_PLAYERS do
		local button = Window:CreateButton(frame, "", 160, 24, function(b)
			self.selected = b.playerName
			self:Refresh(frame)
		end)
		button:SetPoint("TOPLEFT", 4, -34 - (i - 1) * 28)
		button.label:SetJustifyH("LEFT")
		frame.players[i] = button
	end
	frame.header = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.header:SetPoint("TOPLEFT", 184, -32)
	frame.sections = {}
	-- Two columns of sections: 4 left, 3 right.
	for i = 1, 7 do
		local column, slot = i <= 4 and 0 or 1, i <= 4 and i or i - 4
		local section = { rows = {} }
		local x, y = 184 + column * 280, -58 - (slot - 1) * 92
		section.title = Window:CreateText(frame, "GameFontNormal", THEME.gold)
		section.title:SetPoint("TOPLEFT", x, y)
		for r = 1, self.MAX_SECTION_ROWS do
			local label = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
			label:SetPoint("TOPLEFT", x, y - 4 - r * 14)
			label:SetWidth(150)
			local value = Window:CreateText(frame, "GameFontHighlightSmall", THEME.text, "RIGHT")
			value:SetPoint("TOPLEFT", x + 150, y - 4 - r * 14)
			value:SetWidth(120)
			section.rows[r] = { label = label, value = value }
		end
		frame.sections[i] = section
	end
	return frame
end

function Tab:Refresh(frame)
	local profiles = Stats:GetProfiles()
	local selected
	for _, p in ipairs(profiles) do
		if p.name == self.selected then
			selected = p
		end
	end
	selected = selected or profiles[1]
	self.selected = selected and selected.name
	for i, button in ipairs(frame.players) do
		local p = profiles[i]
		if p then
			button.playerName = p.name
			local text = Window:ColorName(p.name, p.class) .. "  |cffb9a988" .. (p.level and L.PROFILE_LEVEL_SHORT:format(p.level) or "") .. "|r"
			if not p.online then
				text = text .. " |cff999999" .. L.OFFLINE_SUFFIX .. "|r"
			end
			button.label:SetText(text)
			button:SetSelected(p.name == self.selected)
			button:Show()
		else
			button.playerName = nil
			button:Hide()
		end
	end
	if not selected then
		return
	end
	frame.header:SetText(Window:ColorName(selected.name, selected.class) .. (selected.isSelf and (" " .. L.YOU_SUFFIX) or ""))
	for i, section in ipairs(Profiles.Sections(selected)) do
		local widgets = frame.sections[i]
		widgets.title:SetText(section.title)
		for r, row in ipairs(widgets.rows) do
			local data = section.rows[r]
			row.label:SetText(data and data[1] or "")
			row.value:SetText(data and data[2] or "")
		end
	end
end

function Stats:RegisterProfilesTab()
	Window:RegisterTab({
		id = "profiles",
		title = L.TAB_PROFILES,
		order = 30,
		create = function(parent)
			return Tab:Create(parent)
		end,
		refresh = function(frame)
			Tab:Refresh(frame)
		end,
	})
end
