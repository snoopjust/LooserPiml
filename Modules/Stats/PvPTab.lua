-- The PvP tab: duels between LooserPiml friends. Duel ladder (ranked
-- only), head to head matrix (Ranked / All duels) and a placeholder for
-- battleground stats. Frame code only: the numbers come from Ladder.lua
-- (pure) and Sync.lua (participants).
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")
local Window = ns.Window
local THEME = Window.THEME

local Tab = {}
Stats.PvPTab = Tab

Tab.MAX_LADDER_ROWS = 6
Tab.ROW_HEIGHT = 20
Tab.NAME_WIDTH = 130
Tab.CELL_WIDTH = 72
Tab.mode = "ranked" -- head to head: "ranked" | "all"

-- Ladder columns: label, x, width, justify
Tab.LADDER_COLUMNS = {
	{ "rank", L.PVP_COL_RANK, 4, 36, "LEFT" },
	{ "name", L.PVP_COL_NAME, 44, 220, "LEFT" },
	{ "wins", L.PVP_COL_WINS, 270, 80, "RIGHT" },
	{ "losses", L.PVP_COL_LOSSES, 360, 80, "RIGHT" },
	{ "rate", L.PVP_COL_RATE, 450, 90, "RIGHT" },
	{ "streak", L.PVP_COL_STREAK, 560, 80, "RIGHT" },
}

local LADDER_TOP = -54
local MATRIX_TOP = -232

local function displayName(entry)
	local name = Window:ColorName(entry.name, entry.class)
	if entry.isSelf then
		return name .. " " .. L.YOU_SUFFIX
	end
	return name
end

local function shortName(entry)
	return Window:ColorName(ns.Roster:Short(entry.name), entry.class)
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

local function textAt(parent, x, y, width, justify, font, color)
	local text = Window:CreateText(parent, font or "GameFontHighlightSmall", color or THEME.text, justify)
	text:SetPoint("TOPLEFT", x, y)
	text:SetWidth(width)
	return text
end

function Tab:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.subtitle = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.subtitle:SetPoint("TOPLEFT", 4, -6)
	frame.subtitle:SetText(L.PVP_SUBTITLE)

	frame.ladderHeader = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.ladderHeader:SetPoint("TOPLEFT", 4, -30)
	frame.ladderHeader:SetText(L.PVP_LADDER)
	for _, column in ipairs(self.LADDER_COLUMNS) do
		textAt(frame, column[3], LADDER_TOP, column[4], column[5], "GameFontNormalSmall", THEME.gold):SetText(column[2])
	end
	frame.ladderRows = {}
	for i = 1, self.MAX_LADDER_ROWS do
		local row = {}
		local y = LADDER_TOP - 18 - (i - 1) * self.ROW_HEIGHT
		for _, column in ipairs(self.LADDER_COLUMNS) do
			row[column[1]] = textAt(frame, column[3], y, column[4], column[5], "GameFontHighlight")
		end
		frame.ladderRows[i] = row
	end
	frame.ladderEmpty = textAt(frame, 44, LADDER_TOP - 18, 640, "LEFT", "GameFontHighlight", THEME.muted)
	frame.ladderEmpty:SetText(L.PVP_LADDER_EMPTY)

	frame.matrixHeader = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.matrixHeader:SetPoint("TOPLEFT", 4, MATRIX_TOP)
	frame.matrixHeader:SetText(L.PVP_HEAD_TO_HEAD)
	frame.matrixHint = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.matrixHint:SetPoint("LEFT", frame.matrixHeader, "RIGHT", 10, 0)
	frame.matrixHint:SetText(L.PVP_MATRIX_HINT)
	frame.modeButtons = {}
	for i, mode in ipairs({ { "ranked", L.PVP_MODE_RANKED }, { "all", L.PVP_MODE_ALL } }) do
		local button = Window:CreateButton(frame, mode[2], 92, 22, function()
			self.mode = mode[1]
			self:Refresh(frame)
		end)
		button:SetPoint("TOPRIGHT", -(2 - i) * 96, MATRIX_TOP + 4)
		button.mode = mode[1]
		frame.modeButtons[i] = button
	end

	-- Matrix: header row (opponents) + one row per winner; last column W – L.
	local max = Stats.Ladder.MAX_MATRIX
	local headerY = MATRIX_TOP - 26
	frame.colHeaders = {}
	for j = 1, max do
		frame.colHeaders[j] = textAt(frame, 4 + self.NAME_WIDTH + (j - 1) * self.CELL_WIDTH, headerY, self.CELL_WIDTH, "CENTER", "GameFontNormalSmall")
	end
	frame.totalHeader = textAt(frame, 4 + self.NAME_WIDTH + max * self.CELL_WIDTH, headerY, 80, "CENTER", "GameFontNormalSmall", THEME.gold)
	frame.totalHeader:SetText(L.PVP_COL_WL)
	frame.matrixRows = {}
	for i = 1, max do
		local y = headerY - 18 - (i - 1) * self.ROW_HEIGHT
		local row = { cells = {}, heat = {} }
		row.name = textAt(frame, 4, y, self.NAME_WIDTH, "LEFT", "GameFontHighlightSmall")
		for j = 1, max do
			local x = 4 + self.NAME_WIDTH + (j - 1) * self.CELL_WIDTH
			local heat = frame:CreateTexture(nil, "BACKGROUND")
			heat:SetTexture(Window.WHITE)
			heat:SetPoint("TOPLEFT", x + 2, y + 3)
			heat:SetSize(self.CELL_WIDTH - 4, self.ROW_HEIGHT - 2)
			heat:Hide()
			row.heat[j] = heat
			row.cells[j] = textAt(frame, x, y, self.CELL_WIDTH, "CENTER", "GameFontHighlight")
		end
		row.total = textAt(frame, 4 + self.NAME_WIDTH + max * self.CELL_WIDTH, y, 80, "CENTER", "GameFontHighlight")
		frame.matrixRows[i] = row
	end
	frame.matrixEmpty = textAt(frame, 44, headerY - 18, 640, "LEFT", "GameFontHighlight", THEME.muted)
	frame.matrixEmpty:SetText(L.PVP_MATRIX_EMPTY)

	frame.bgHeader = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	frame.bgHeader:SetPoint("BOTTOMLEFT", 4, 8)
	frame.bgHeader:SetText(L.PVP_BATTLEGROUNDS)
	return frame
end

----------------------------------------------------------------------
-- Filling
----------------------------------------------------------------------

function Tab:Refresh(frame)
	local Ladder = Stats.Ladder
	local participants = Stats:GetParticipants("all")
	local merged = Ladder.Merge(participants)

	local rows = Ladder.Rows(participants, merged)
	for i, widgets in ipairs(frame.ladderRows) do
		local row = rows[i]
		for _, column in ipairs(self.LADDER_COLUMNS) do
			local text = ""
			if row then
				local key = column[1]
				if key == "rank" then
					text = "#" .. row.rank
				elseif key == "name" then
					text = displayName(row)
				elseif key == "rate" then
					text = string.format("%d%%", math.floor(row.rate * 100 + 0.5))
				elseif key == "streak" then
					text = row.streakText
				else
					text = tostring(row[key])
				end
			end
			widgets[column[1]]:SetText(text)
		end
	end
	if #rows == 0 then
		frame.ladderEmpty:Show()
	else
		frame.ladderEmpty:Hide()
	end

	for _, button in ipairs(frame.modeButtons) do
		button:SetSelected(button.mode == self.mode)
	end
	local matrix = Ladder.Matrix(participants, self.mode, merged)
	local players = matrix.players
	for j, header in ipairs(frame.colHeaders) do
		header:SetText(players[j] and shortName(players[j]) or "")
	end
	if #players >= 2 then
		frame.totalHeader:Show()
		frame.matrixEmpty:Hide()
	else
		frame.totalHeader:Hide()
		frame.matrixEmpty:Show()
	end
	local bronze, gold = THEME.bronze, THEME.gold
	for i, widgets in ipairs(frame.matrixRows) do
		local player = #players >= 2 and players[i]
		widgets.name:SetText(player and shortName(player) or "")
		for j, cell in ipairs(widgets.cells) do
			local heat = widgets.heat[j]
			heat:Hide()
			if player and players[j] then
				if i == j then
					cell:SetText(L.PVP_DIAGONAL)
					cell:SetTextColor(THEME.muted[1], THEME.muted[2], THEME.muted[3])
				else
					local level = matrix.heat[i][j]
					cell:SetText(tostring(matrix.cells[i][j]))
					local c = level > 0 and gold or THEME.text
					cell:SetTextColor(c[1], c[2], c[3])
					if level > 0 then
						heat:SetVertexColor(bronze[1], bronze[2], bronze[3], level == 2 and 0.8 or 0.35)
						heat:Show()
					end
				end
			else
				cell:SetText("")
			end
		end
		widgets.total:SetText(player and string.format("%d – %d", matrix.wins[i], matrix.losses[i]) or "")
	end
end

function Stats:RegisterPvPTab()
	Window:RegisterTab({
		id = "pvp",
		title = L.TAB_PVP,
		order = 35,
		create = function(parent)
			return Tab:Create(parent)
		end,
		refresh = function(frame)
			Tab:Refresh(frame)
		end,
	})
end
