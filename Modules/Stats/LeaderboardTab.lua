-- The Leaderboard tab of the main window, plus the stats lines of the
-- minimap tooltip. Frame code only: the numbers come from
-- Leaderboard.lua (pure) and Sync.lua (participants).
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")
local Window = ns.Window

local Tab = {}
Stats.LeaderboardTab = Tab

Tab.PERIODS = {
	{ id = "tonight", label = L.PERIOD_TONIGHT },
	{ id = "week", label = L.PERIOD_WEEK },
	{ id = "all", label = L.PERIOD_ALL },
}
Tab.METRIC_LABELS = {
	deaths = L.METRIC_DEATHS,
	gold = L.METRIC_GOLD,
	quests = L.METRIC_QUESTS,
	levelups = L.METRIC_LEVELUPS,
}
Tab.AWARD_LABELS = {
	deathKing = L.AWARD_DEATH_KING,
	fishFood = L.AWARD_FISH_FOOD,
	goldHoarder = L.AWARD_GOLD_HOARDER,
	speedrunner = L.AWARD_SPEEDRUNNER,
}
-- Raid target icons and the gold coin exist in every client (raid icons
-- confirmed in-game; gold coin TODO(verify in-game)).
Tab.AWARD_ICONS = {
	deathKing = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
	fishFood = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
	goldHoarder = "Interface\\MoneyFrame\\UI-GoldIcon",
	speedrunner = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
}
Tab.MAX_ROWS = 10
Tab.ROW_HEIGHT = 24
Tab.BAR_WIDTH = 360

Tab.period = "tonight"
Tab.metric = "deaths"

local THEME = Window.THEME

local function displayName(entry)
	local name = Window:ColorName(entry.name, entry.class)
	if entry.isSelf then
		return name .. " " .. L.YOU_SUFFIX
	end
	return name
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function Tab:CreateCard(parent, index)
	local card = Window:CreatePanel(parent)
	card:SetSize(176, 92)
	card:SetPoint("TOPLEFT", (index - 1) * 184, -50)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(28, 28)
	card.icon:SetPoint("TOPLEFT", 10, -10)
	card.award = Window:CreateText(card, "GameFontNormal", THEME.gold)
	card.award:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
	card.winner = Window:CreateText(card, "GameFontHighlightLarge", THEME.text)
	card.winner:SetPoint("TOPLEFT", 10, -48)
	card.winner:SetWidth(156)
	card.value = Window:CreateText(card, "GameFontHighlightSmall", THEME.muted)
	card.value:SetPoint("TOPLEFT", 10, -70)
	return card
end

function Tab:CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(720, self.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -186 - (index - 1) * self.ROW_HEIGHT)
	row.rank = Window:CreateText(row, "GameFontNormal", THEME.gold)
	row.rank:SetPoint("LEFT", 4, 0)
	row.rank:SetWidth(36)
	row.name = Window:CreateText(row, "GameFontHighlight", THEME.text)
	row.name:SetPoint("LEFT", 44, 0)
	row.name:SetWidth(190)
	row.barBg = row:CreateTexture(nil, "BACKGROUND")
	row.barBg:SetTexture(Window.WHITE)
	row.barBg:SetVertexColor(THEME.panel[1], THEME.panel[2], THEME.panel[3], 1)
	row.barBg:SetPoint("LEFT", 240, 0)
	row.barBg:SetSize(self.BAR_WIDTH, 14)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetTexture(Window.WHITE)
	row.bar:SetVertexColor(THEME.bronze[1], THEME.bronze[2], THEME.bronze[3], 1)
	row.bar:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)
	row.bar:SetHeight(14)
	row.value = Window:CreateText(row, "GameFontHighlight", THEME.text, "RIGHT")
	row.value:SetPoint("RIGHT", -4, 0)
	row.value:SetWidth(110)
	return row
end

function Tab:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.subtitle = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.subtitle:SetPoint("TOPLEFT", 4, -6)
	frame.subtitle:SetText(L.LEADERBOARD_SUBTITLE)

	frame.periodButtons = {}
	for i, period in ipairs(self.PERIODS) do
		local button = Window:CreateButton(frame, period.label, 92, 22, function()
			self.period = period.id
			self:Refresh(frame)
		end)
		button:SetPoint("TOPRIGHT", -(#self.PERIODS - i) * 96, 0)
		button.periodId = period.id
		frame.periodButtons[i] = button
	end

	frame.hallHeader = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.hallHeader:SetPoint("TOPLEFT", 4, -30)
	frame.hallHeader:SetText(L.HALL_OF_FAME)
	frame.cards = {}
	for i = 1, #Stats.Leaderboard.AWARDS do
		frame.cards[i] = self:CreateCard(frame, i)
	end

	frame.rankHeader = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.rankHeader:SetPoint("TOPLEFT", 4, -158)
	frame.rankHeader:SetText(L.RANKING)
	frame.metricButtons = {}
	for i, metric in ipairs(Stats.Leaderboard.METRICS) do
		local button = Window:CreateButton(frame, self.METRIC_LABELS[metric.id], 104, 22, function()
			self.metric = metric.id
			self:Refresh(frame)
		end)
		button:SetPoint("TOPRIGHT", -(#Stats.Leaderboard.METRICS - i) * 108, -154)
		button.metricId = metric.id
		frame.metricButtons[i] = button
	end
	frame.rows = {}
	for i = 1, self.MAX_ROWS do
		frame.rows[i] = self:CreateRow(frame, i)
	end
	frame.empty = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.empty:SetPoint("TOPLEFT", 44, -190)
	frame.empty:SetText(L.LEADERBOARD_EMPTY)
	return frame
end

----------------------------------------------------------------------
-- Filling
----------------------------------------------------------------------

function Tab:Refresh(frame)
	local Leaderboard = Stats.Leaderboard
	for _, button in ipairs(frame.periodButtons) do
		button:SetSelected(button.periodId == self.period)
	end
	for _, button in ipairs(frame.metricButtons) do
		button:SetSelected(button.metricId == self.metric)
	end

	local participants = Stats:GetParticipants(self.period)

	for i, card in ipairs(Leaderboard.HallOfFame(participants)) do
		local widget = frame.cards[i]
		widget.icon:SetTexture(self.AWARD_ICONS[card.award.id])
		widget.award:SetText(self.AWARD_LABELS[card.award.id])
		if card.winner then
			widget.winner:SetText(displayName(card.winner))
			widget.value:SetText(Leaderboard.Format(card.winner.value, card.award.format))
		else
			widget.winner:SetText(L.NO_ONE_YET)
			widget.value:SetText("")
		end
	end

	local rows, metric = Leaderboard.Ranking(participants, self.metric)
	for i, widget in ipairs(frame.rows) do
		local row = rows[i]
		if row then
			widget.rank:SetText("#" .. row.rank)
			local name = displayName(row)
			if not row.online and not row.isSelf then
				name = name .. " |cff999999" .. L.OFFLINE_SUFFIX .. "|r"
			end
			widget.name:SetText(name)
			widget.value:SetText(Leaderboard.Format(row.value, metric.format))
			local width = math.max(1, math.floor(self.BAR_WIDTH * row.fraction))
			widget.bar:SetWidth(width)
			if row.fraction > 0 then
				widget.bar:Show()
			else
				widget.bar:Hide()
			end
			widget:Show()
		else
			widget:Hide()
		end
	end
	if #rows <= 1 then
		frame.empty:Show() -- only me so far
	else
		frame.empty:Hide()
	end
end

----------------------------------------------------------------------
-- Minimap tooltip lines
----------------------------------------------------------------------

function Tab:FillTooltip(tooltip)
	local participants = Stats:GetParticipants("tonight")
	local deaths = 0
	for _, p in ipairs(participants) do
		deaths = deaths + Stats.Model.Get(p.agg, "deaths")
	end
	local king = Stats.Leaderboard.Award(participants, "deathKing")
	local muted, text = THEME.muted, THEME.text
	tooltip:AddLine(" ")
	tooltip:AddLine(L.TOOLTIP_FRIENDS_ONLINE:format(Stats:CountOnlineFriends()), text[1], text[2], text[3])
	tooltip:AddLine(L.TOOLTIP_TONIGHT_DEATHS:format(deaths), text[1], text[2], text[3])
	if king then
		tooltip:AddLine(L.TOOLTIP_DEATH_KING:format(Window:ColorName(king.name, king.class), king.value), text[1], text[2], text[3])
	else
		tooltip:AddLine(L.TOOLTIP_DEATH_KING_NONE, muted[1], muted[2], muted[3])
	end
end

function Stats:RegisterUI()
	Window:RegisterTab({
		id = "leaderboard",
		title = L.TAB_LEADERBOARD,
		order = 10,
		create = function(parent)
			return Tab:Create(parent)
		end,
		refresh = function(frame)
			Tab:Refresh(frame)
		end,
	})
	Window:AddTooltipProvider(function(tooltip)
		if self:IsEnabled() then
			Tab:FillTooltip(tooltip)
		end
	end)
end
