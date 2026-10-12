-- Settings registry and the Blizzard Settings panel (Options > AddOns >
-- LooserPiml).
--
-- Core services and modules register their own options here; the values
-- stay in their own SavedVariables (each option has get/set functions).
-- After login the registry builds the Blizzard panel from the definitions,
-- using proxy settings, so the panel always shows the live values even if
-- they were changed by a slash command.
--
-- Item fields:
--   type     "checkbox" | "slider" | "button"
--   key      unique id ("ticker.death"), not needed for buttons
--   label, tooltip
--   get(), set(value)                checkbox/slider
--   default                          checkbox/slider
--   min, max, step, format(value)    slider
--   buttonText, onClick()            button
--
-- Pages with their own frame (lists that change at runtime, like the
-- friends list) are registered with AddCanvas and become subcategories
-- (Options > AddOns > LooserPiml > Title).
local _, ns = ...
local L = ns.L

local Options = {}
ns:RegisterCore("Options", Options)

Options.sections = {} -- ordered: { id, title, items }
Options.canvases = {} -- ordered: { id, title, create() -> frame }

local function findSection(id)
	for _, section in ipairs(Options.sections) do
		if section.id == id then
			return section
		end
	end
	return nil
end

-- Sections appear in the order of `order` (lower first), then registration.
function Options:AddSection(id, title, order)
	local section = findSection(id)
	if section then
		return section
	end
	section = { id = id, title = title, order = order or (#self.sections + 1) * 10, items = {} }
	self.sections[#self.sections + 1] = section
	table.sort(self.sections, function(a, b)
		return a.order < b.order
	end)
	return section
end

function Options:Add(sectionId, item)
	local section = assert(findSection(sectionId), "unknown options section " .. tostring(sectionId))
	section.items[#section.items + 1] = item
	return item
end

function Options:Find(key)
	for _, section in ipairs(self.sections) do
		for _, item in ipairs(section.items) do
			if item.key == key then
				return item
			end
		end
	end
	return nil
end

function Options:Get(key)
	local item = self:Find(key)
	return item and item.get and item.get()
end

function Options:Set(key, value)
	local item = assert(self:Find(key), "unknown option " .. tostring(key))
	if item.type == "slider" then
		value = ns.Util.Clamp(value, item.min, item.max)
	end
	item.set(value)
	ns.Events:Fire("LP_OPTION_CHANGED", key, value)
end

-- A settings page with its own frame. create() is called once, when the
-- panel is built; the frame should refresh itself in OnShow.
function Options:AddCanvas(id, title, create)
	self.canvases[#self.canvases + 1] = { id = id, title = title, create = create }
end

----------------------------------------------------------------------
-- Blizzard Settings panel
----------------------------------------------------------------------
-- Signatures from Blizzard's Forever UI code (Blizzard_Settings.lua,
-- Blizzard_SettingControls.lua, build 1.60.1):
--   Settings.RegisterVerticalLayoutCategory(name) -> category, layout
--   Settings.RegisterProxySetting(category, variable, varType, name, default, get, set)
--   Settings.CreateCheckbox(category, setting, tooltip)
--   Settings.CreateSlider(category, setting, options, tooltip)
--   CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)
--   CreateSettingsListSectionHeaderInitializer(name, tooltip)
--   Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name) -> subcategory
--   Settings.OpenToCategory(categoryID)

local function variableName(key)
	return "LooserPiml_" .. key:gsub("[^%w]", "_")
end

function Options:BuildPanel()
	if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
		if not self.category then
			ns.Log:Debug("Settings API not available, options panel not created")
		end
		return
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON_NAME)
	if not layout and SettingsPanel and SettingsPanel.GetLayout then
		layout = SettingsPanel:GetLayout(category)
	end
	local varType = Settings.VarType or { Boolean = "boolean", Number = "number" }
	for _, section in ipairs(self.sections) do
		if layout and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(section.title))
		end
		for _, item in ipairs(section.items) do
			if item.type == "checkbox" then
				local setting = Settings.RegisterProxySetting(category, variableName(item.key), varType.Boolean,
					item.label, item.default, item.get, function(value)
						self:Set(item.key, value)
					end)
				Settings.CreateCheckbox(category, setting, item.tooltip)
			elseif item.type == "slider" then
				local setting = Settings.RegisterProxySetting(category, variableName(item.key), varType.Number,
					item.label, item.default, item.get, function(value)
						self:Set(item.key, value)
					end)
				local options = Settings.CreateSliderOptions(item.min, item.max, item.step)
				if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
					options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, item.format)
				end
				Settings.CreateSlider(category, setting, options, item.tooltip)
			elseif item.type == "button" and layout and CreateSettingsButtonInitializer then
				layout:AddInitializer(CreateSettingsButtonInitializer(item.label, item.buttonText, function()
					ns.SafeCall(item.onClick)
				end, item.tooltip, true))
			end
		end
	end
	self.subcategories = {}
	if Settings.RegisterCanvasLayoutSubcategory then
		for _, canvas in ipairs(self.canvases) do
			local frame = canvas.create()
			self.subcategories[canvas.id] = Settings.RegisterCanvasLayoutSubcategory(category, frame, canvas.title)
		end
	end
	Settings.RegisterAddOnCategory(category)
	self.category = category
end

-- Opens the LooserPiml settings, or one of its canvas pages (subcategoryId).
function Options:Open(subcategoryId)
	local category = self.category
	if subcategoryId and self.subcategories and self.subcategories[subcategoryId] then
		category = self.subcategories[subcategoryId]
	end
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
		return true
	end
	ns.Log:Print(L.OPTIONS_UNAVAILABLE)
	return false
end

----------------------------------------------------------------------
-- Confirmation dialog (StaticPopup, Blizzard's standard yes/no dialog)
----------------------------------------------------------------------

function Options:Confirm(id, text, onAccept)
	local name = "LOOSERPIML_" .. id
	if not (StaticPopupDialogs and StaticPopup_Show) then
		return false
	end
	StaticPopupDialogs[name] = StaticPopupDialogs[name] or {
		text = text,
		button1 = YES,
		button2 = NO,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopupDialogs[name].OnAccept = function()
		ns.SafeCall(onAccept)
	end
	StaticPopup_Show(name)
	return true
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Options:OnInitialize()
	ns.Slash:Register("options", function()
		self:Open()
	end, "", L.HELP_OPTIONS)
end

-- After every module registered its options in OnInitialize/OnEnable.
function Options:OnEnable()
	C_Timer.After(0, function()
		self:BuildPanel()
	end)
end
