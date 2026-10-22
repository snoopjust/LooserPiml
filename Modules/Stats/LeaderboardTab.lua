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
	duelKing = L.AWARD_DUEL_KING,
	broke = L.SHAME_BROKE,
	noob = L.SHAME_NOOB,
	looserPiml = L.SHAME_LOOSERPIML,
	slowpoke = L.SHAME_SLOWPOKE,
	bossSnack = L.SHAME_BOSS_SNACK,
	kangaroo = L.SHAME_KANGAROO,
}
-- Raid target icons and the coins exist in every client (raid icons
-- confirmed in-game; gold coin seen in-game 2026-10-20; copper coin
-- TODO(verify in-game), same folder).
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
Tab.AWARD_ICONS = {
	deathKing = RAID_ICON .. "8",
	fishFood = RAID_ICON .. "6",
	goldHoarder = "Interface\\MoneyFrame\\UI-GoldIcon",
	speedrunner = RAID_ICON .. "1",
	duelKing = RAID_ICON .. "7",
	broke = "Interface\\MoneyFrame\\UI-CopperIcon",
	noob = RAID_ICON .. "4",
	looserPiml = RAID_ICON .. "8",
	slowpoke = RAID_ICON .. "5",
	bossSnack = RAID_ICON .. "2",
	kangaroo = RAID_ICON .. "3",
}
-- The cards share the content width (736 px): five Fame cards, six Shame.
Tab.CONTENT_WIDTH, Tab.CARD_GAP = 736, 8
Tab.CARD_WIDTH = 140
Tab.MAX_CARDS = 6
Tab.hall = "fame" -- "fame" | "shame"
Tab.MAX_ROWS = 10
Tab.ROW_HEIGHT = 24
Tab.BAR_WIDTH = 300

Tab.period = "tonight"
Tab.metric = "deaths"

local THEME = Window.THEME

local function displayName(entry)
	local name = Window:ColorName(entry.name, entry.class)
	if entry.isSelf then
		name = name .. " " .. L.YOU_SUFFIX
	end
	return name .. Window:NameBadge(entry.name)
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function Tab:CreateCard(parent, index)
	local card = Window:CreatePanel(parent)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(28, 28)
	card.icon:SetPoint("TOPLEFT", 10, -10)
	card.award = Window:CreateText(card, "GameFontNormal", THEME.gold)
	card.award:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
	card.winner = Window:CreateText(card, "GameFontHighlightLarge", THEME.text)
	card.winner:SetPoint("TOPLEFT", 10, -48)
	card.value = Window:CreateText(card, "GameFontHighlightSmall", THEME.muted)
	card.value:SetPoint("TOPLEFT", 10, -70)
	-- One line each; a long name or amount is cut ("...") instead of
	-- running into the next card.
	card.winner:SetWordWrap(false)
	card.value:SetWordWrap(false)
	self:PlaceCard(card, index, 5)
	return card
end

-- Card `index` of `count` across the content width.
function Tab:PlaceCard(card, index, count)
	local width = math.floor((self.CONTENT_WIDTH - (count - 1) * self.CARD_GAP) / count)
	card:ClearAllPoints()
	card:SetSize(width, 92)
	card:SetPoint("TOPLEFT", (index - 1) * (width + self.CARD_GAP), -50)
	card.winner:SetWidth(width - 20)
	card.value:SetWidth(width - 20)
	card.width = width
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
	row.value:SetWidth(170) -- room for "1234g 56s right now"
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
	-- Fame | Shame: the same cards, switched (decided 2026-10-22).
	frame.hallButtons = {}
	for i, hall in ipairs({ { "fame", L.HALL_FAME_BUTTON }, { "shame", L.HALL_SHAME_BUTTON } }) do
		local button = Window:CreateButton(frame, hall[2], 64, 20, function()
			self.hall = hall[1]
			self:Refresh(frame)
		end)
		button:SetPoint("TOPLEFT", 150 + (i - 1) * 68, -28)
		button.hall = hall[1]
		frame.hallButtons[i] = button
	end
	frame.cards = {}
	for i = 1, self.MAX_CARDS do
		frame.cards[i] = self:CreateCard(frame, i)
	end

	frame.rankHeader = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.rankHeader:SetPoint("TOPLEFT", 4, -158)
	frame.rankHeader:SetText(L.RANKING)
	-- Shown for snapshot metrics (gold): the period buttons still switch the
	-- other cards and metrics, but not this ranking.
	frame.metricNote = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.metricNote:SetPoint("LEFT", frame.rankHeader, "RIGHT", 10, 0)
	frame.metricNote:SetText(L.GOLD_RIGHT_NOW_NOTE)
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

-- The small line under a card's winner: "71g 60s right now", "Lv 3",
-- "1 – 6 ranked", "1h 05m", "7".
function Tab.CardValue(card)
	local award, value = card.award, card.winner.value
	local text = Stats.Leaderboard.Format(value, award.format)
	if award.metric == "gold" then
		return L.RIGHT_NOW:format(text)
	elseif award.metric == "level" then
		return L.PROFILE_LEVEL_SHORT:format(value)
	elseif award.format == "record" then
		return L.SHAME_RECORD:format(text)
	end
	return text
end

function Tab:Refresh(frame)
	local Leaderboard = Stats.Leaderboard
	local participants = Stats:GetParticipants(self.period)
	local rows, metric = Leaderboard.Ranking(participants, self.metric)
	for _, button in ipairs(frame.periodButtons) do
		button:SetSelected(button.periodId == self.period)
	end
	for _, button in ipairs(frame.metricButtons) do
		button:SetSelected(button.metricId == self.metric)
	end
	if metric.snapshot then
		frame.metricNote:Show()
	else
		frame.metricNote:Hide()
	end

	local shame = self.hall == "shame"
	for _, button in ipairs(frame.hallButtons) do
		button:SetSelected(button.hall == self.hall)
	end
	frame.hallHeader:SetText(shame and L.HALL_OF_SHAME or L.HALL_OF_FAME)
	local cards = shame and Leaderboard.HallOfShame(participants) or Leaderboard.HallOfFame(participants)
	for i, widget in ipairs(frame.cards) do
		local card = cards[i]
		if card then
			self:PlaceCard(widget, i, #cards)
			widget.icon:SetTexture(self.AWARD_ICONS[card.award.id])
			widget.award:SetText(self.AWARD_LABELS[card.award.id])
			if card.winner then
				-- No badge on the cards: they are too narrow for it.
				local name = Window:ColorName(card.winner.name, card.winner.class)
				widget.winner:SetText(card.winner.isSelf and (name .. " " .. L.YOU_SUFFIX) or name)
				widget.value:SetText(self.CardValue(card))
			else
				widget.winner:SetText(L.NO_ONE_YET)
				widget.value:SetText("")
			end
			widget:Show()
		else
			widget:Hide()
		end
	end

	for i, widget in ipairs(frame.rows) do
		local row = rows[i]
		if row then
			widget.rank:SetText("#" .. row.rank)
			local name = displayName(row)
			if not row.online and not row.isSelf then
				name = name .. " |cff999999" .. L.OFFLINE_SUFFIX .. "|r"
			end
			widget.name:SetText(name)
			local value = Leaderboard.Format(row.value, metric.format)
			if metric.snapshot then
				value = L.RIGHT_NOW:format(value) -- gold on hand: "71g 60s right now"
			end
			widget.value:SetText(value)
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
	if #participants <= 1 then
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
	local looser = Stats.Leaderboard.LooserPiml(participants)
	if looser then
		tooltip:AddLine(L.TOOLTIP_LOOSERPIML:format(Window:ColorName(looser.name, looser.class)), text[1], text[2], text[3])
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
