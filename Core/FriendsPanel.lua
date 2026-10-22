-- The LooserPiml friends list UI. One panel design, built twice: as the
-- "Friends" tab of the main window and as the settings page
-- Options > AddOns > LooserPiml > Friends. Both show the same list
-- (Core/Friends.lua) and refresh when it changes.
--
-- Add by name (edit box), add from the current group (one button per real
-- group member who isn't listed yet; never the fake test-mode members),
-- add from the WoW character friends list (online ones first), remove per
-- row. Removing takes effect at once: nothing is sent to that player any
-- more, not even messages that are still held.
local _, ns = ...
local L = ns.L

local Panel = {}
ns:RegisterCore("FriendsPanel", Panel)

Panel.MAX_ROWS = 7
Panel.MAX_CANDIDATES = 5 -- buttons per "Add from ..." row
Panel.ROW_HEIGHT = 24
Panel.LIST_TOP = -218 -- y of the first list row

Panel.instances = {} -- every built panel, refreshed together

local Window = ns.Window
local THEME = Window.THEME

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------

function Panel:CreateRow(frame, index)
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(560, self.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 4, self.LIST_TOP - (index - 1) * self.ROW_HEIGHT)
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

-- A label plus MAX_CANDIDATES "+ Name" buttons and a line for "nobody".
function Panel:CreateCandidateRow(frame, label, y)
	local line = { buttons = {} }
	line.label = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	line.label:SetPoint("TOPLEFT", 4, y - 4)
	line.label:SetText(label)
	for i = 1, self.MAX_CANDIDATES do
		local button = Window:CreateButton(frame, "", 84, 20, function(b)
			if b.member then
				local full, err = ns.Friends:Add(b.member)
				self:SetMessage(full and L.FRIENDS_ADDED:format(full) or err)
			end
		end)
		button:SetPoint("TOPLEFT", 150 + (i - 1) * 88, y)
		line.buttons[i] = button
	end
	line.none = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	line.none:SetPoint("TOPLEFT", 150, y - 4)
	line.none:SetWidth(430)
	return line
end

-- Fills a candidate row; returns how many candidates didn't fit.
function Panel:FillCandidates(line, candidates, noneText)
	for i, button in ipairs(line.buttons) do
		local member = candidates[i]
		if member then
			button.member = member.name
			local name = Window:ColorName(member.name, member.class)
			if member.connected == false then
				name = "|cff999999" .. ns.Roster:Short(member.name) .. "|r" -- offline WoW friend
			end
			button.label:SetText("+ " .. name)
			button:Show()
		else
			button.member = nil
			button:Hide()
		end
	end
	if #candidates == 0 then
		line.none:SetText(noneText)
		line.none:Show()
	else
		line.none:Hide()
	end
	return math.max(0, #candidates - self.MAX_CANDIDATES)
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
	frame.input = Window:CreateEditBox(frame, 200)
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

	-- Add from group / from the WoW friends list
	frame.fromGroup = self:CreateCandidateRow(frame, L.FRIENDS_ADD_FROM_GROUP, -122)
	frame.fromWoW = self:CreateCandidateRow(frame, L.FRIENDS_ADD_FROM_WOW, -148)
	frame.wowHint = Window:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	frame.wowHint:SetPoint("TOPLEFT", 150, -172)
	frame.wowHint:SetWidth(430)
	frame.wowHint:SetText(L.FRIENDS_WOW_HINT)

	-- The list
	frame.listHeader = Window:CreateText(frame, "GameFontNormal", THEME.gold)
	frame.listHeader:SetPoint("TOPLEFT", 4, self.LIST_TOP + 22)
	frame.rows = {}
	for i = 1, self.MAX_ROWS do
		frame.rows[i] = self:CreateRow(frame, i)
	end
	frame.empty = Window:CreateText(frame, "GameFontHighlight", THEME.muted)
	frame.empty:SetPoint("TOPLEFT", 8, self.LIST_TOP - 4)
	frame.empty:SetWidth(560)
	frame.empty:SetText(L.FRIENDS_EMPTY)

	-- Paging, only when the list is longer than MAX_ROWS
	frame.prev = Window:CreateButton(frame, "<", 28, 20, function()
		frame.page = math.max(1, frame.page - 1)
		self:Refresh(frame)
	end)
	frame.prev:SetPoint("TOPLEFT", 4, self.LIST_TOP - 4 - self.MAX_ROWS * self.ROW_HEIGHT)
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

	local more = self:FillCandidates(frame.fromGroup, Friends:GetGroupCandidates(),
		ns.Roster:IsInGroup() and L.FRIENDS_NO_CANDIDATES or L.FRIENDS_NOT_IN_GROUP)
	more = more + self:FillCandidates(frame.fromWoW, Friends:GetWoWFriendCandidates(), L.FRIENDS_NO_WOW_CANDIDATES)
	if more > 0 and not self.messageText then
		-- More than fit on the buttons (a raid, a long friends list).
		frame.message:SetText(L.FRIENDS_MORE_CANDIDATES:format(more))
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
			-- Badges (the LooserPiml title) go with the status: the name
			-- column is full with "First -Surname" on the megaserver.
			row.status:SetText(Friends:StatusText(friend) .. Window:NameBadge(friend.name))
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
