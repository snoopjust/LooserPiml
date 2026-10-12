-- The LooserPiml friends list UI. One panel design, built twice: as the
-- "Friends" tab of the main window and as the settings page
-- Options > AddOns > LooserPiml > Friends. Both show the same list
-- (Core/Friends.lua) and refresh when it changes.
--
-- Add by name (edit box), add from the current group (one button per real
-- group member who isn't listed yet; never the fake test-mode members),
-- remove per row. Removing takes effect at once: nothing is sent to that
-- player any more, not even messages that are still held.
local _, ns = ...
local L = ns.L

local Panel = {}
ns:RegisterCore("FriendsPanel", Panel)

Panel.MAX_ROWS = 8
Panel.MAX_CANDIDATES = 10 -- "Add from group" buttons (two rows of five)
Panel.ROW_HEIGHT = 24

Panel.instances = {} -- every built panel, refreshed together

local Window = ns.Window
local THEME = Window.THEME

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

-- An edit box in the window's look. Plain EditBox + BackdropTemplate, so
-- it doesn't depend on Blizzard's input box templates.
local function createEditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetTextInsets(6, 6, 0, 0)
	box:SetMaxLetters(64)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = Window.WHITE, edgeFile = Window.WHITE, edgeSize = 1 })
		box:SetBackdropColor(THEME.background[1], THEME.background[2], THEME.background[3], 1)
		box:SetBackdropBorderColor(THEME.bronze[1], THEME.bronze[2], THEME.bronze[3], 1)
	end
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	return box
end

function Panel:CreateRow(frame, index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(560, self.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 4, -206 - (index - 1) * self.ROW_HEIGHT)
	row.name = Window:CreateText(row, "GameFontHighlight", THEME.text)
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWidth(220)
	row.status = Window:CreateText(row, "GameFontHighlightSmall", THEME.muted)
	row.status:SetPoint("LEFT", 230, 0)
	row.status:SetWidth(230)
	row.remove = Window:CreateButton(row, L.FRIENDS_REMOVE, 80, 20, function()
		local name = row.friend -- Remove refreshes the rows, read it first
		if name then
			ns.Friends:Remove(name)
			self:SetMessage(L.FRIENDS_REMOVED:format(name))
		end
	end)
	row.remove:SetPoint("RIGHT", -4, 0)
	return row
end

function Panel:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(600, 440)
	frame.page = 1

	frame.title = Window:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	frame.title:SetPoint("TOPLEFT", 4, -6)
	frame.title:SetText(L.FRIENDS_TITLE)
	frame.help = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.help:SetPoint("TOPLEFT", 4, -30)
	frame.help:SetWidth(580)
	frame.help:SetText(L.FRIENDS_HELP)

	-- Add by name
	frame.addLabel = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	frame.addLabel:SetPoint("TOPLEFT", 4, -80)
	frame.addLabel:SetText(L.FRIENDS_ADD_BY_NAME)
	frame.input = createEditBox(frame, 200)
	frame.input:SetPoint("TOPLEFT", 150, -76)
	local function submit()
		local full, err = ns.Friends:Add(frame.input:GetText() or "")
		if full then
			frame.input:SetText("")
			frame.input:ClearFocus()
			self:SetMessage(L.FRIENDS_ADDED:format(full))
		else
			self:SetMessage(err)
		end
	end
	frame.input:SetScript("OnEnterPressed", submit)
	frame.addButton = Window:CreateButton(frame, L.FRIENDS_ADD, 80, 22, submit)
	frame.addButton:SetPoint("LEFT", frame.input, "RIGHT", 8, 0)
	frame.message = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.message:SetPoint("TOPLEFT", 150, -102)
	frame.message:SetWidth(430)

	-- Add from group
	frame.groupLabel = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	frame.groupLabel:SetPoint("TOPLEFT", 4, -126)
	frame.groupLabel:SetText(L.FRIENDS_ADD_FROM_GROUP)
	frame.candidates = {}
	for i = 1, self.MAX_CANDIDATES do
		local button = Window:CreateButton(frame, "", 84, 20, function(b)
			if b.member then
				local full, err = ns.Friends:Add(b.member)
				self:SetMessage(full and L.FRIENDS_ADDED:format(full) or err)
			end
		end)
		local column, line = (i - 1) % 5, math.floor((i - 1) / 5)
		button:SetPoint("TOPLEFT", 150 + column * 88, -122 - line * 24)
		frame.candidates[i] = button
	end
	frame.noCandidates = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.noCandidates:SetPoint("TOPLEFT", 150, -126)
	frame.noCandidates:SetWidth(430)

	-- The list
	frame.listHeader = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	frame.listHeader:SetPoint("TOPLEFT", 4, -184)
	frame.rows = {}
	for i = 1, self.MAX_ROWS do
		frame.rows[i] = self:CreateRow(frame, i)
	end
	frame.empty = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.empty:SetPoint("TOPLEFT", 8, -210)
	frame.empty:SetWidth(560)
	frame.empty:SetText(L.FRIENDS_EMPTY)

	-- Paging, only when the list is longer than MAX_ROWS
	frame.prev = Window:CreateButton(frame, "<", 28, 20, function()
		frame.page = math.max(1, frame.page - 1)
		self:Refresh(frame)
	end)
	frame.prev:SetPoint("TOPLEFT", 4, -210 - self.MAX_ROWS * self.ROW_HEIGHT)
	frame.next = Window:CreateButton(frame, ">", 28, 20, function()
		frame.page = frame.page + 1
		self:Refresh(frame)
	end)
	frame.next:SetPoint("LEFT", frame.prev, "RIGHT", 4, 0)
	frame.pageText = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.pageText:SetPoint("LEFT", frame.next, "RIGHT", 8, 0)

	frame:SetScript("OnShow", function()
		self:Refresh(frame)
	end)
	self.instances[#self.instances + 1] = frame
	self:Refresh(frame)
	return frame
end

----------------------------------------------------------------------
-- Filling
----------------------------------------------------------------------

-- Feedback line under the edit box, shown on every panel.
function Panel:SetMessage(text)
	self.messageText = text
	for _, frame in ipairs(self.instances) do
		frame.message:SetText(text or "")
	end
end

function Panel:Refresh(frame)
	local Friends = ns.Friends
	frame.message:SetText(self.messageText or "")

	local candidates = Friends:GetGroupCandidates()
	for i, button in ipairs(frame.candidates) do
		local member = candidates[i]
		if member then
			button.member = member.name
			button.label:SetText("+ " .. Window:ColorName(member.name, member.class))
			button:Show()
		else
			button.member = nil
			button:Hide()
		end
	end
	if #candidates == 0 then
		frame.noCandidates:SetText(ns.Roster:IsInGroup() and L.FRIENDS_NO_CANDIDATES or L.FRIENDS_NOT_IN_GROUP)
		frame.noCandidates:Show()
	elseif #candidates > self.MAX_CANDIDATES then
		frame.noCandidates:Hide()
		-- More strangers than buttons (a raid): type the name instead.
		frame.message:SetText(L.FRIENDS_MORE_CANDIDATES:format(#candidates - self.MAX_CANDIDATES))
	else
		frame.noCandidates:Hide()
	end

	local list = Friends:GetList()
	frame.listHeader:SetText(L.FRIENDS_LIST_HEADER:format(#list, Friends.MAX_FRIENDS))
	local pages = math.max(1, math.ceil(#list / self.MAX_ROWS))
	frame.page = math.min(math.max(frame.page or 1, 1), pages)
	local first = (frame.page - 1) * self.MAX_ROWS
	for i, row in ipairs(frame.rows) do
		local friend = list[first + i]
		if friend then
			row.friend = friend.name
			local short, realm = friend.name:match("^([^%-]+)%-(.+)$")
			local name = Window:ColorName(friend.name, friend.class)
			if realm then
				name = name .. " |cff999999-" .. realm:gsub("|", "||") .. "|r"
			end
			row.name:SetText(short and name or friend.name)
			row.status:SetText(Friends:StatusText(friend))
			row:Show()
		else
			row.friend = nil
			row:Hide()
		end
	end
	if #list == 0 then
		frame.empty:Show()
	else
		frame.empty:Hide()
	end
	if pages > 1 then
		frame.prev:Show()
		frame.next:Show()
		frame.pageText:SetText(L.FRIENDS_PAGE:format(frame.page, pages))
		frame.pageText:Show()
	else
		frame.prev:Hide()
		frame.next:Hide()
		frame.pageText:Hide()
	end
end

function Panel:RefreshAll()
	for _, frame in ipairs(self.instances) do
		if frame:IsShown() then
			self:Refresh(frame)
		end
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Panel:OnInitialize()
	local Options = ns.Options
	-- A section on the main settings page that leads to the list page (a
	-- list with a button per entry needs its own frame, see AddCanvas).
	Options:AddSection("friends", L.OPT_SECTION_FRIENDS, 5)
	Options:Add("friends", {
		type = "button", label = L.OPT_FRIENDS_MANAGE, buttonText = L.OPT_FRIENDS_MANAGE_BUTTON, tooltip = L.OPT_FRIENDS_MANAGE_TIP,
		onClick = function()
			Options:Open("friends")
		end,
	})
	Options:AddCanvas("friends", L.FRIENDS_TITLE, function()
		local frame = self:Create(nil)
		frame:Hide()
		return frame
	end)
	Window:RegisterTab({
		id = "friends",
		title = L.TAB_FRIENDS,
		order = 90,
		create = function(parent)
			return self:Create(parent)
		end,
		refresh = function(frame)
			self:Refresh(frame)
		end,
	})
end

function Panel:OnEnable()
	ns.Events:Register(self, "LP_FRIENDS_CHANGED", "RefreshAll")
	ns.Events:Register(self, "LP_ROSTER_UPDATED", "RefreshAll")
	ns.Events:Register(self, "FRIENDLIST_UPDATE", "RefreshAll")
end
