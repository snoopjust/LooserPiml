-- The small "ranked duel?" panel shown while a duel with a connected
-- LooserPiml friend is pending (Duels.lua decides when). Frame code only.
--
-- It sits below Blizzard's duel dialog if that one is shown (challenged
-- side), otherwise near the screen center (challenger side: the game shows
-- the challenger no dialog). The panel never touches Blizzard's dialog: it
-- is only anchored to it. Its two buttons exchange the ranked choice and do
-- nothing else; accepting or declining stays in the game's dialog.
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")
local Window = ns.Window
local THEME = Window.THEME

local Panel = {}
Stats.DuelPanel = Panel

Panel.WIDTH, Panel.HEIGHT = 340, 148
Panel.CENTER_OFFSET_Y = 140 -- above the center, where the game's dialogs are not

local function opponentName(cur)
	return ns.Roster:ColorName(cur.opponent, Stats.Duels.ClassOf(cur.opponent))
end

function Panel:Get()
	if self.frame then
		return self.frame
	end
	local frame = Window:CreatePanel(UIParent, THEME.background, THEME.bronze)
	frame:SetSize(self.WIDTH, self.HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()

	frame.title = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	frame.title:SetPoint("TOPLEFT", 12, -10)
	frame.title:SetText(L.DUEL_PANEL_TITLE)
	frame.record = Window:CreateText(frame, "GameFontHighlightSmall", THEME.text)
	frame.record:SetPoint("TOPLEFT", 12, -30)
	frame.record:SetWidth(self.WIDTH - 24)

	frame.ranked = Window:CreateButton(frame, L.DUEL_RANKED, 150, 24, function()
		Stats.Duels:Pick("ranked")
	end)
	frame.ranked:SetPoint("TOPLEFT", 12, -50)
	frame.fun = Window:CreateButton(frame, L.DUEL_FUN, 150, 24, function()
		Stats.Duels:Pick("fun")
	end)
	frame.fun:SetPoint("TOPRIGHT", -12, -50)

	frame.note = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.note:SetPoint("TOPLEFT", 12, -82)
	frame.note:SetWidth(self.WIDTH - 24)
	frame.note:SetText(L.DUEL_NOTE)
	-- Right below the note (its height follows the text), not at the
	-- bottom, so there is no gap in between.
	frame.status = Window:CreateText(frame, "GameFontHighlightSmall", THEME.gold)
	frame.status:SetPoint("TOPLEFT", frame.note, "BOTTOMLEFT", 0, -10)
	frame.status:SetWidth(self.WIDTH - 24)
	self.frame = frame
	return frame
end

-- Below Blizzard's duel dialog when it is shown, else near the center.
-- Anchoring our own frame to theirs doesn't change their frame; pcall in
-- case the client refuses the anchor (it then falls back to the center).
-- StaticPopup_FindVisible(which) exists in Forever's UI code and Blizzard's
-- "DUEL_REQUESTED" dialog is a StaticPopup; TODO(verify in-game) that the
-- anchor looks right.
function Panel:Anchor(frame)
	frame:ClearAllPoints()
	local popup = StaticPopup_FindVisible and StaticPopup_FindVisible("DUEL_REQUESTED")
	if popup and not ns.IsSecret(popup) and pcall(frame.SetPoint, frame, "TOP", popup, "BOTTOM", 0, -8) then
		frame.anchoredToDialog = true
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, self.CENTER_OFFSET_Y)
	frame.anchoredToDialog = false
end

function Panel:Open(cur)
	local frame = self:Get()
	self:Anchor(frame)
	self:Refresh(cur)
	frame:Show()
end

function Panel:Close()
	if self.frame then
		self.frame:Hide()
	end
end

function Panel:IsShown()
	return self.frame ~= nil and self.frame:IsShown()
end

-- The status line for the current choices.
function Panel.StatusText(cur)
	local name = opponentName(cur)
	if cur.theirs == "off" then
		return L.DUEL_STATUS_OFF:format(name)
	elseif cur.mine == "fun" then
		return L.DUEL_STATUS_MINE_FUN
	elseif cur.mine == "ranked" then
		if cur.theirs == "ranked" then
			return L.DUEL_STATUS_BOTH_RANKED
		elseif cur.theirs == "fun" then
			return L.DUEL_STATUS_THEIRS_FUN:format(name)
		end
		return L.DUEL_STATUS_WAITING:format(name)
	elseif cur.theirs == "ranked" then
		return L.DUEL_STATUS_THEY_RANKED:format(name)
	elseif cur.theirs == "fun" then
		return L.DUEL_STATUS_THEIRS_FUN:format(name)
	end
	return L.DUEL_STATUS_NONE
end

function Panel:Refresh(cur)
	local frame = self.frame
	if not frame or not cur then
		return
	end
	local record = Stats.Duels:GetRecord(cur.opponent)
	local text = L.DUEL_RECORD:format(opponentName(cur), record.rw, record.rl)
	if cur.test then
		text = L.TEST_TAG .. " " .. text
	end
	frame.record:SetText(text)
	frame.ranked:SetSelected(cur.mine == "ranked")
	frame.fun:SetSelected(cur.mine == "fun")
	frame.status:SetText(self.StatusText(cur))
end
