-- The Tonight tab and the evening recap.
--
-- "Tonight" is the gaming day since 06:00 local time (Model.DayStart).
-- Tab, top to bottom:
--   recap card   tonight's awards that have data (Death King, Fish Food,
--                most level-ups, most quests, most gold looted)
--   KPI tiles    session duration, deaths, level-ups, gold looted, duels
--                (sums over me and my LooserPiml friends)
--   timeline     own events and friends' ticker events tonight, newest at
--                the bottom, from Core/Timeline (kept 7 days, survives
--                /reload)
--
-- Evening recap: on the first login after the 06:00 boundary, a local
-- popup "Last evening: ..." with the previous evening's recap (setting
-- "Show evening recap"). Shown once per evening, never sent anywhere.
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")
local Window = ns.Window
local THEME = Window.THEME

local Tonight = {}
Stats.Tonight = Tonight

Tonight.RECAP_DELAY = 10     -- seconds after login (friends' stats arrive meanwhile)
Tonight.RECAP_HIDE_AFTER = 60
Tonight.MAX_TIMELINE = 13
Tonight.MAX_RECAP_CARDS = 5

-- Recap awards: like the Hall of Fame, but only period aggregates (no
-- snapshot like current gold).
Tonight.AWARDS = {
	{ id = "deathKing", label = L.AWARD_DEATH_KING, metric = "deaths", better = "high", tieKey = "deaths", format = "number" },
	{ id = "fishFood", label = L.AWARD_FISH_FOOD, metric = "drowned", better = "high", tieKey = "drowned", format = "number" },
	{ id = "levelUps", label = L.RECAP_MOST_LEVELUPS, metric = "levelUps", better = "high", tieKey = "levelUps", format = "number" },
	{ id = "quests", label = L.RECAP_MOST_QUESTS, metric = "quests", better = "high", tieKey = "quests", format = "number" },
	{ id = "looted", label = L.RECAP_MOST_LOOTED, metric = "moneyLooted", better = "high", format = "money" },
}

----------------------------------------------------------------------
-- Data (pure apart from the participants)
----------------------------------------------------------------------

-- Awards with a winner: { { award, winner } }
function Tonight.Recap(participants)
	local cards = {}
	for _, award in ipairs(Tonight.AWARDS) do
		local winner = Stats.Leaderboard.Award(participants, award)
		if winner then
			cards[#cards + 1] = { award = award, winner = winner }
		end
	end
	return cards
end

-- Sums over all participants: { deaths, levelUps, moneyLooted, duels }
function Tonight.Totals(participants)
	local Model = Stats.Model
	local totals = { deaths = 0, levelUps = 0, moneyLooted = 0, duels = 0 }
	for _, p in ipairs(participants) do
		local agg = p.agg
		totals.deaths = totals.deaths + Model.Get(agg, "deaths")
		totals.levelUps = totals.levelUps + Model.Get(agg, "levelUps")
		totals.moneyLooted = totals.moneyLooted + Model.Get(agg, "moneyLooted")
		totals.duels = totals.duels + Model.Get(agg, "duelsWon") + Model.Get(agg, "duelsLost")
	end
	return totals
end

-- Seconds played this session, counted from 06:00 at the earliest.
function Stats:SessionDuration(now)
	now = now or GetServerTime()
	local start = math.max(self.sessionStart or now, self.Model.DayStart(now))
	return math.max(0, now - start)
end

-- Participants of a past gaming day: my aggregate of that day, plus
-- friends whose cached "tonight" belongs to that day.
function Stats:GetParticipantsOfDay(dayKey)
	local char = self:GetChar()
	local list = {
		{ name = ns.Roster:GetPlayerName(), class = ns.Roster:GetPlayerClass(), isSelf = true, agg = self.Model.AggregateDay(char.log, char.buckets, dayKey) },
	}
	for name, entry in pairs(ns.Friends:GetDB()) do
		local cached = self.db.friendStats[name]
		if entry.handshake and cached and cached.day == dayKey and cached.stats and cached.stats.tonight then
			list[#list + 1] = { name = name, class = cached.class or entry.class, agg = cached.stats.tonight }
		end
	end
	return list
end

----------------------------------------------------------------------
-- Evening recap popup
----------------------------------------------------------------------

-- "Death King: Max (5) · Most level-ups: Lena (2)", totals line
function Tonight.RecapLines(participants)
	local lines = {}
	for _, card in ipairs(Tonight.Recap(participants)) do
		lines[#lines + 1] = L.RECAP_LINE:format(card.award.label, Window:ColorName(card.winner.name, card.winner.class),
			Stats.Leaderboard.Format(card.winner.value, card.award.format))
	end
	local totals = Tonight.Totals(participants)
	local any = #lines > 0 or totals.deaths + totals.levelUps + totals.moneyLooted + totals.duels > 0
	lines[#lines + 1] = L.RECAP_TOTALS:format(totals.deaths, totals.levelUps, ns.Util.FormatMoney(totals.moneyLooted), totals.duels)
	return lines, any
end

function Stats:ShowEveningRecap(dayKey)
	local lines, any = Tonight.RecapLines(self:GetParticipantsOfDay(dayKey))
	if not any then
		return false -- nothing happened that evening worth a popup
	end
	local frame = self.recapFrame
	if not frame then
		frame = Window:CreatePanel(UIParent, THEME.background, THEME.bronze)
		frame:SetSize(460, 60)
		frame:SetPoint("TOP", 0, -140)
		frame:SetFrameStrata("DIALOG")
		frame.title = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
		frame.title:SetPoint("TOPLEFT", 14, -12)
		frame.body = Window:CreateText(frame, "GameFontHighlight", THEME.text)
		frame.body:SetPoint("TOPLEFT", 14, -38)
		frame.body:SetWidth(432)
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
		close:SetScript("OnClick", function()
			frame:Hide()
		end)
		self.recapFrame = frame
	end
	local y, m, d = dayKey:match("^(%d+)-(%d+)-(%d+)$")
	local when = (y and date("%a %d %b", time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))) or dayKey
	frame.title:SetText(L.RECAP_TITLE:format(when))
	frame.body:SetText(table.concat(lines, "\n"))
	frame:SetHeight(52 + #lines * 16)
	frame:Show()
	C_Timer.After(Tonight.RECAP_HIDE_AFTER, function()
		frame:Hide()
	end)
	return true
end

-- On the first login of a new gaming day: last active day's recap, once.
function Stats:CheckEveningRecap()
	local previous = self.previousActiveDay
	local today = self.Model.DayKey(GetServerTime())
	if self.db.showRecap == false or not previous or previous >= today or self.db.recapShownFor == previous then
		return false
	end
	self.db.recapShownFor = previous
	return self:ShowEveningRecap(previous)
end

----------------------------------------------------------------------
-- The tab
----------------------------------------------------------------------

local Tab = {}
Stats.TonightTab = Tab

Tab.KPIS = {
	{ id = "session", label = L.KPI_SESSION },
	{ id = "deaths", label = L.KPI_DEATHS },
	{ id = "levelUps", label = L.KPI_LEVELUPS },
	{ id = "moneyLooted", label = L.KPI_LOOTED },
	{ id = "duels", label = L.KPI_DUELS },
}

function Tab:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.recap = Window:CreatePanel(frame)
	frame.recap:SetPoint("TOPLEFT", 0, 0)
	frame.recap:SetSize(736, 70)
	frame.recap.title = Window:CreateText(frame.recap, "GameFontNormal", THEME.gold)
	frame.recap.title:SetPoint("TOPLEFT", 10, -8)
	frame.recap.title:SetText(L.TONIGHT_RECAP_TITLE)
	frame.recap.cards = {}
	for i = 1, Tonight.MAX_RECAP_CARDS do
		local text = Window:CreateText(frame.recap, "GameFontHighlightSmall", THEME.text)
		text:SetPoint("TOPLEFT", 10 + (i - 1) * 144, -30)
		text:SetWidth(140)
		frame.recap.cards[i] = text
	end
	frame.recap.empty = Window:CreateText(frame.recap, "GameFontHighlightSmall", THEME.muted)
	frame.recap.empty:SetPoint("TOPLEFT", 10, -32)
	frame.recap.empty:SetText(L.TONIGHT_RECAP_EMPTY)

	frame.tiles = {}
	for i, kpi in ipairs(self.KPIS) do
		local tile = Window:CreatePanel(frame)
		tile:SetSize(140, 52)
		tile:SetPoint("TOPLEFT", (i - 1) * 149, -80)
		tile.value = Window:CreateText(tile, "GameFontNormalLarge", THEME.gold, "CENTER")
		tile.value:SetPoint("TOP", 0, -8)
		tile.value:SetWidth(134)
		tile.label = Window:CreateText(tile, "GameFontHighlightSmall", THEME.muted, "CENTER")
		tile.label:SetPoint("BOTTOM", 0, 8)
		tile.label:SetText(kpi.label)
		tile.kpi = kpi.id
		frame.tiles[i] = tile
	end

	frame.timelineHeader = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.timelineHeader:SetPoint("TOPLEFT", 4, -144)
	frame.timelineHeader:SetText(L.TONIGHT_TIMELINE)
	frame.lines = {}
	for i = 1, Tonight.MAX_TIMELINE do
		local line = Window:CreateText(frame, "GameFontHighlightSmall", THEME.text)
		line:SetPoint("TOPLEFT", 4, -152 - i * 18)
		line:SetWidth(720)
		frame.lines[i] = line
	end
	frame.empty = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.empty:SetPoint("TOPLEFT", 4, -172)
	frame.empty:SetText(L.TONIGHT_EMPTY)
	return frame
end

function Tab:Refresh(frame)
	local now = GetServerTime()
	local participants = Stats:GetParticipants("tonight")
	local cards = Tonight.Recap(participants)
	for i, text in ipairs(frame.recap.cards) do
		local card = cards[i]
		if card then
			text:SetText(card.award.label .. "\n" .. Window:ColorName(card.winner.name, card.winner.class) .. " |cffb9a988"
				.. Stats.Leaderboard.Format(card.winner.value, card.award.format) .. "|r")
			text:Show()
		else
			text:Hide()
		end
	end
	if #cards == 0 then
		frame.recap.empty:Show()
	else
		frame.recap.empty:Hide()
	end

	local totals = Tonight.Totals(participants)
	for _, tile in ipairs(frame.tiles) do
		local value
		if tile.kpi == "session" then
			value = ns.Util.FormatDuration(Stats:SessionDuration(now))
		elseif tile.kpi == "moneyLooted" then
			value = ns.Util.FormatMoney(totals.moneyLooted)
		else
			value = tostring(totals[tile.kpi])
		end
		tile.value:SetText(value)
	end

	local entries = ns.Timeline:Between(Stats.Model.DayStart(now))
	local first = math.max(1, #entries - Tonight.MAX_TIMELINE + 1) -- newest at the bottom
	for i, line in ipairs(frame.lines) do
		local entry = entries[first + i - 1]
		if entry then
			line:SetText("|cffb9a988" .. date("%H:%M", entry.t) .. "|r  " .. (entry.i and (entry.i .. " ") or "") .. (entry.x or ""))
			line:Show()
		else
			line:Hide()
		end
	end
	if #entries == 0 then
		frame.empty:Show()
	else
		frame.empty:Hide()
	end
end

function Stats:RegisterTonightTab()
	Window:RegisterTab({
		id = "tonight",
		title = L.TAB_TONIGHT,
		order = 15,
		create = function(parent)
			return Tab:Create(parent)
		end,
		refresh = function(frame)
			Tab:Refresh(frame)
		end,
	})
	ns.Options:Add("stats", {
		type = "checkbox", key = "stats.showRecap", label = L.OPT_SHOW_RECAP, tooltip = L.OPT_SHOW_RECAP_TIP, default = true,
		get = function()
			return self.db.showRecap ~= false
		end,
		set = function(value)
			self.db.showRecap = value and true or false
		end,
	})
end
