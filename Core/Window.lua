-- The main window shell, the minimap button and the Addon Compartment
-- entry, so friends never need slash commands.
--
-- The window is generic: modules register tabs (ns.Window:RegisterTab) and
-- minimap-tooltip lines (ns.Window:AddTooltipProvider). Tabs now:
-- Leaderboard, Tonight, Profiles, PvP (Stats module), Inventory (Inventory
-- module) and Friends (Core/FriendsPanel.lua).
--
-- Look (approved mockup): dark brown background, bronze borders, gold
-- headings, class-colored names, the game's own fonts, no emoji.
local ADDON_NAME, ns = ...
local L = ns.L

local Window = {}
ns:RegisterCore("Window", Window)

Window.FRAME_NAME = "LooserPimlMainFrame"
Window.WIDTH, Window.HEIGHT = 760, 560
Window.REFRESH_DELAY = 0.5 -- seconds; coalesces bursts of data changes

-- Colors from the mockup as { r, g, b } (0..1)
local function hex(code)
	return {
		tonumber(code:sub(1, 2), 16) / 255,
		tonumber(code:sub(3, 4), 16) / 255,
		tonumber(code:sub(5, 6), 16) / 255,
	}
end
Window.THEME = {
	background = hex("1b1611"),
	panel = hex("241d16"),
	border = hex("4a3a26"),
	bronze = hex("7a5c34"),
	gold = hex("e5b85c"),
	text = hex("ece2cf"),
	muted = hex("b9a988"),
}
local THEME = Window.THEME

-- A flat texture from a solid color (Interface\Buttons\WHITE8X8 is a plain
-- white texture shipped with every client).
Window.WHITE = "Interface\\Buttons\\WHITE8X8"

Window.tabs = {}             -- ordered { id, title, order, create(parent) -> frame, refresh(frame) }
Window.tooltipProviders = {} -- function(tooltip)

----------------------------------------------------------------------
-- Small widget helpers (shared with module tabs)
----------------------------------------------------------------------

-- BackdropTemplate is required for SetBackdrop on Mainline-style clients
-- (Forever includes Blizzard_SharedXML/Backdrop.lua).
function Window:CreatePanel(parent, color, borderColor, name)
	local panel = CreateFrame("Frame", name, parent, "BackdropTemplate")
	if panel.SetBackdrop then
		panel:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
		local c, b = color or THEME.panel, borderColor or THEME.border
		panel:SetBackdropColor(c[1], c[2], c[3], 0.97)
		panel:SetBackdropBorderColor(b[1], b[2], b[3], 1)
	end
	return panel
end

function Window:CreateText(parent, fontObject, color, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
	local c = color or THEME.text
	text:SetTextColor(c[1], c[2], c[3])
	text:SetJustifyH(justify or "LEFT")
	return text
end

-- Flat button with a label; selected buttons get the bronze fill.
function Window:CreateButton(parent, label, width, height, onClick)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width or 100, height or 22)
	if button.SetBackdrop then
		button:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	end
	button.label = self:CreateText(button, "GameFontHighlightSmall", THEME.text, "CENTER")
	button.label:SetPoint("CENTER")
	button.label:SetText(label)
	button:SetScript("OnClick", function(self, mouseButton)
		ns.SafeCall(onClick, self, mouseButton)
	end)
	function button:SetSelected(selected)
		self.selected = selected
		if self.SetBackdropColor then
			local fill = selected and THEME.bronze or THEME.panel
			self:SetBackdropColor(fill[1], fill[2], fill[3], 1)
			self:SetBackdropBorderColor(THEME.bronze[1], THEME.bronze[2], THEME.bronze[3], 1)
		end
		local c = selected and THEME.gold or THEME.text
		self.label:SetTextColor(c[1], c[2], c[3])
	end
	button:SetSelected(false)
	return button
end

-- An edit box in the window's look. Plain EditBox + BackdropTemplate, so
-- it doesn't depend on Blizzard's input box templates.
function Window:CreateEditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetTextInsets(6, 6, 0, 0)
	box:SetMaxLetters(64)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
		box:SetBackdropColor(THEME.background[1], THEME.background[2], THEME.background[3], 1)
		box:SetBackdropBorderColor(THEME.bronze[1], THEME.bronze[2], THEME.bronze[3], 1)
	end
	box:SetScript("OnEscapePressed", function(b)
		b:ClearFocus()
	end)
	return box
end

-- "|cffRRGGBBName|r" in class color (or the muted color if unknown).
function Window:ColorName(name, class)
	return ns.Roster:ColorName(name, class)
end

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

function Window:RegisterTab(tab)
	self.tabs[#self.tabs + 1] = tab
	table.sort(self.tabs, function(a, b)
		return (a.order or 50) < (b.order or 50)
	end)
end

function Window:AddTooltipProvider(fn)
	self.tooltipProviders[#self.tooltipProviders + 1] = fn
end

-- Badges after a player's name (e.g. the LooserPiml title, Stats module):
-- providers return a short colored text or nil. Core panels (Friends) use
-- them without knowing the modules.
Window.badgeProviders = {}

function Window:AddBadgeProvider(fn)
	self.badgeProviders[#self.badgeProviders + 1] = fn
end

-- " · Badge" for a full name, or "".
function Window:NameBadge(fullName)
	local parts = {}
	for _, provider in ipairs(self.badgeProviders) do
		local ok, badge = pcall(provider, fullName)
		if ok and type(badge) == "string" and badge ~= "" then
			parts[#parts + 1] = badge
		end
	end
	if #parts == 0 then
		return ""
	end
	return "  " .. table.concat(parts, " ")
end

----------------------------------------------------------------------
-- Main frame
----------------------------------------------------------------------

function Window:GetDB()
	return ns.DB:Get("window")
end

function Window:Create()
	if self.frame then
		return self.frame
	end
	-- Named so UISpecialFrames can close it with ESC (it stores names).
	local frame = self:CreatePanel(UIParent, THEME.background, THEME.bronze, self.FRAME_NAME)
	frame:SetSize(self.WIDTH, self.HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local point, _, relativePoint, x, y = f:GetPoint(1)
		self:GetDB().point = { point, relativePoint, x, y }
	end)
	frame:Hide()
	table.insert(UISpecialFrames, self.FRAME_NAME)

	-- Title bar
	local title = self:CreateText(frame, "GameFontNormalLarge", THEME.gold)
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText(L.WINDOW_TITLE)
	frame.title = title

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function()
		self:Hide()
	end)

	-- Tab bar
	frame.tabButtons = {}
	local x = 16
	for _, tab in ipairs(self.tabs) do
		local button = self:CreateButton(frame, tab.title, 110, 24, function()
			self:SelectTab(tab.id)
		end)
		button:SetPoint("TOPLEFT", x, -44)
		button.tabId = tab.id
		frame.tabButtons[#frame.tabButtons + 1] = button
		x = x + 114
	end

	-- Content area (tabs create their frames in here on first use)
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 12, -76)
	content:SetPoint("BOTTOMRIGHT", -12, 44)
	frame.content = content
	frame.tabFrames = {}

	-- Footer: version status + settings
	local footer = self:CreateText(frame, "GameFontHighlightSmall", THEME.muted)
	footer:SetPoint("BOTTOMLEFT", 16, 16)
	frame.footer = footer
	local settings = self:CreateButton(frame, L.WINDOW_SETTINGS, 110, 22, function()
		ns.Options:Open()
	end)
	settings:SetPoint("BOTTOMRIGHT", -14, 12)
	frame.settingsButton = settings

	self.frame = frame
	self:ApplyPosition()
	return frame
end

function Window:ApplyPosition()
	local point = self:GetDB().point
	self.frame:ClearAllPoints()
	if type(point) == "table" and point[1] then
		self.frame:SetPoint(point[1], UIParent, point[2] or point[1], point[3] or 0, point[4] or 0)
	else
		self.frame:SetPoint("CENTER")
	end
end

function Window:SelectTab(id)
	local frame = self:Create()
	local selected
	for _, tab in ipairs(self.tabs) do
		if tab.id == id then
			selected = tab
		end
	end
	selected = selected or self.tabs[1]
	if not selected then
		return
	end
	self.selectedTab = selected.id
	for _, button in ipairs(frame.tabButtons) do
		button:SetSelected(button.tabId == selected.id)
	end
	for tabId, tabFrame in pairs(frame.tabFrames) do
		if tabId ~= selected.id then
			tabFrame:Hide()
		end
	end
	local tabFrame = frame.tabFrames[selected.id]
	if not tabFrame then
		tabFrame = selected.create(frame.content)
		tabFrame:SetAllPoints(frame.content)
		frame.tabFrames[selected.id] = tabFrame
	end
	tabFrame:Show()
	self:Refresh()
end

function Window:Refresh()
	local frame = self.frame
	if not frame or not frame:IsShown() then
		return
	end
	frame.footer:SetText(self:GetVersionStatus())
	for _, tab in ipairs(self.tabs) do
		local tabFrame = frame.tabFrames[tab.id]
		if tabFrame and tabFrame:IsShown() and tab.refresh then
			ns.SafeCall(tab.refresh, tabFrame)
		end
	end
end

-- Coalesces many data changes (e.g. several stats messages) into one redraw.
function Window:ScheduleRefresh()
	if self.refreshScheduled or not (self.frame and self.frame:IsShown()) then
		return
	end
	self.refreshScheduled = true
	C_Timer.After(self.REFRESH_DELAY, function()
		self.refreshScheduled = false
		self:Refresh()
	end)
end

function Window:Open(tabId)
	local frame = self:Create()
	frame:Show()
	self:SelectTab(tabId or self.selectedTab)
end

function Window:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

function Window:Toggle()
	if self.frame and self.frame:IsShown() then
		self:Hide()
	else
		self:Open()
	end
end

function Window:IsShown()
	return self.frame ~= nil and self.frame:IsShown()
end

----------------------------------------------------------------------
-- Footer: version status of friends seen this session
----------------------------------------------------------------------

function Window:GetVersionStatus()
	local Version = ns.Version
	local mine = Version:GetCurrent()
	local newest = Version.Parse(mine) and mine or nil -- dev builds don't count
	for _, info in pairs(Version.known) do
		if Version.Parse(info.version) and (not newest or Version.Compare(info.version, newest) == 1) then
			newest = info.version
		end
	end
	local outdated = {}
	for name, info in pairs(Version.known) do
		if newest and Version.Compare(info.version, newest) == -1 then
			outdated[#outdated + 1] = string.format("%s (%s)", ns.Roster:Short(name), info.version)
		end
	end
	table.sort(outdated)
	local text = L.WINDOW_VERSION:format(mine)
	if newest and Version.Compare(mine, newest) == -1 then
		return text .. "  ·  " .. L.WINDOW_UPDATE_AVAILABLE:format(newest)
	elseif #outdated > 0 then
		return text .. "  ·  " .. L.WINDOW_OUTDATED:format(table.concat(outdated, ", "))
	elseif next(Version.known) then
		return text .. "  ·  " .. L.WINDOW_ALL_CURRENT
	end
	return text .. "  ·  " .. L.WINDOW_NO_FRIENDS_YET
end

----------------------------------------------------------------------
-- Minimap button (LibDataBroker launcher + LibDBIcon) and tooltip
----------------------------------------------------------------------

Window.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

function Window:FillTooltip(tooltip)
	tooltip:AddLine(L.ADDON_NAME, THEME.gold[1], THEME.gold[2], THEME.gold[3])
	tooltip:AddLine(L.TOOLTIP_LEFT_CLICK, THEME.text[1], THEME.text[2], THEME.text[3])
	tooltip:AddLine(L.TOOLTIP_RIGHT_CLICK, THEME.text[1], THEME.text[2], THEME.text[3])
	for _, provider in ipairs(self.tooltipProviders) do
		ns.SafeCall(provider, tooltip)
	end
end

function Window:OnLauncherClick(mouseButton)
	if mouseButton == "RightButton" then
		ns.Options:Open()
	else
		self:Toggle()
	end
end

function Window:CreateLauncher()
	local LDB = LibStub("LibDataBroker-1.1", true)
	local DBIcon = LibStub("LibDBIcon-1.0", true)
	if not (LDB and DBIcon) then
		ns.Log:Debug("LibDataBroker/LibDBIcon missing, no minimap button")
		return
	end
	self.launcher = LDB:NewDataObject(ADDON_NAME, {
		type = "launcher",
		text = ADDON_NAME,
		icon = self.ICON,
		OnClick = function(_, mouseButton)
			self:OnLauncherClick(mouseButton)
		end,
		OnTooltipShow = function(tooltip)
			self:FillTooltip(tooltip)
		end,
	})
	-- LibDBIcon stores the button angle (minimapPos) and hide flag in here.
	DBIcon:Register(ADDON_NAME, self.launcher, ns.DB:Get("minimap"))
	self.dbIcon = DBIcon
end

function Window:SetMinimapShown(shown)
	ns.DB:Get("minimap").hide = not shown
	if self.dbIcon then
		if shown then
			self.dbIcon:Show(ADDON_NAME)
		else
			self.dbIcon:Hide(ADDON_NAME)
		end
	end
end

----------------------------------------------------------------------
-- Addon Compartment (the addon list button on the minimap, Midnight/Forever)
----------------------------------------------------------------------
-- The game finds these through "## AddonCompartmentFunc..." in the .toc and
-- calls them by global name, so they have to be globals.
-- Click: (addonName, mouseButton). Enter/leave: (addonName, menuButton).

function LooserPiml_OnAddonCompartmentClick(_, mouseButton)
	Window:OnLauncherClick(mouseButton)
end

function LooserPiml_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	Window:FillTooltip(GameTooltip)
	GameTooltip:Show()
end

function LooserPiml_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Window:OnInitialize()
	ns.Options:AddSection("minimap", L.OPT_SECTION_MINIMAP, 40)
	ns.Options:Add("minimap", {
		type = "checkbox", key = "minimap.show", label = L.OPT_MINIMAP_SHOW, default = true,
		get = function()
			return not ns.DB:Get("minimap").hide
		end,
		set = function(value)
			self:SetMinimapShown(value)
		end,
	})
	ns.Slash:Register("stats", function(arg)
		if arg:lower() == "chat" then
			ns.Events:Fire("LP_PRINT_STATS") -- the Ticker's text ranking
		else
			self:Open()
		end
	end, "[chat]", L.HELP_STATS)
end

function Window:OnEnable()
	self:CreateLauncher()
	ns.Events:Register(self, "LP_STATS_CHANGED", "ScheduleRefresh")
	ns.Events:Register(self, "LP_FRIENDS_CHANGED", "ScheduleRefresh")
	ns.Events:Register(self, "LP_INVENTORY_CHANGED", "ScheduleRefresh")
	ns.Events:Register(self, "LP_ITEM_LOADED", "ScheduleRefresh") -- an item name arrived from the cache
	ns.Events:Register(self, "LP_WISHLIST_CHANGED", "ScheduleRefresh")
	ns.Events:Register(self, "LP_TIMELINE_CHANGED", "ScheduleRefresh")
	ns.Events:Register(self, "LP_BADGES_CHANGED", "ScheduleRefresh") -- a name badge moved (LooserPiml title)
end
