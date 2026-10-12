-- Minimal World of Warcraft API mock for running LooserPiml (and its real
-- libraries) under plain Lua 5.1.
--
-- Every Mock is one simulated game client with its own global environment
-- (via setfenv), clock, frames and timers. Several clients can share a
-- Network, so messages really travel from one client's AceComm to another's.
--
-- The mock enforces the safety constraints: calling SendChatMessage (visible
-- chat) raises an error, and addon messages must be <= 255 bytes without NUL.
local Mock = {}
Mock.__index = Mock

local CLASS_COLORS = {
	WARRIOR = "ffc69b6d", PALADIN = "fff48cba", HUNTER = "ffaad372", ROGUE = "fffff468",
	PRIEST = "ffffffff", SHAMAN = "ff0070dd", MAGE = "ff3fc7eb", WARLOCK = "ff8788ee",
	DRUID = "ffff7c0a",
}

local SEND_RESULT = {
	Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
	InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7,
	ChannelThrottle = 8, GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11,
	TargetOffline = 12,
}
Mock.SEND_RESULT = SEND_RESULT

----------------------------------------------------------------------
-- Secret values
----------------------------------------------------------------------

local SecretMeta = {
	__index = function() error("attempt to index a secret value", 2) end,
	__lt = function() error("attempt to compare a secret value", 2) end,
	__le = function() error("attempt to compare a secret value", 2) end,
	__concat = function() error("attempt to concatenate a secret value", 2) end,
	__len = function() error("attempt to get length of a secret value", 2) end,
	__add = function() error("attempt to perform arithmetic on a secret value", 2) end,
	__sub = function() error("attempt to perform arithmetic on a secret value", 2) end,
	__mul = function() error("attempt to perform arithmetic on a secret value", 2) end,
	__call = function() error("attempt to call a secret value", 2) end,
}

function Mock.Secret()
	return setmetatable({}, SecretMeta)
end

local function isSecret(value)
	return type(value) == "table" and getmetatable(value) == SecretMeta
end

----------------------------------------------------------------------
-- Network
----------------------------------------------------------------------

local Network = {}
Network.__index = Network

function Mock.NewNetwork()
	return setmetatable({ clients = {}, pending = {} }, Network)
end

function Network:Add(client)
	self.clients[#self.clients + 1] = client
	client.net = self
end

function Network:Flush()
	local pending = self.pending
	self.pending = {}
	for _, msg in ipairs(pending) do
		local sender = msg.from:FullName()
		for _, client in ipairs(self.clients) do
			local deliver
			if msg.chatType == "WHISPER" then
				deliver = client:MatchesName(msg.target)
			else
				-- Group channels reach everyone, including the sender (echo).
				deliver = client ~= msg.from or client.echoGroup
			end
			if deliver then
				client.received[#client.received + 1] = msg
				client:Fire("CHAT_MSG_ADDON", msg.prefix, msg.text, msg.chatType, sender, sender, 0, 0, "", 0)
			end
		end
	end
end

-- Steps every client's clock in lockstep and delivers messages in between.
function Network:Advance(seconds)
	local remaining = seconds or 0
	repeat
		local dt = math.min(0.1, remaining)
		for _, client in ipairs(self.clients) do
			client:Step(dt)
		end
		self:Flush()
		remaining = remaining - dt
	until remaining <= 1e-9
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------

local FrameMethods = {}

function FrameMethods:RegisterEvent(event)
	if self.mock.invalidEvents[event] then
		error("Attempt to register unknown event \"" .. event .. "\"", 2)
	end
	self.events[event] = true
end
function FrameMethods:UnregisterEvent(event) self.events[event] = nil end
function FrameMethods:UnregisterAllEvents() self.events = {} end
function FrameMethods:IsEventRegistered(event) return self.events[event] == true end
function FrameMethods:SetScript(script, fn) self.scripts[script] = fn end
function FrameMethods:GetScript(script) return self.scripts[script] end
function FrameMethods:Show() self.shown = true end
function FrameMethods:Hide() self.shown = false end
function FrameMethods:IsShown() return self.shown end
function FrameMethods:SetText(text) self.text_ = text end
function FrameMethods:GetText() return self.text_ end
function FrameMethods:GetFont() return self.fontPath or "Fonts\\FRIZQT__.TTF", self.fontSize or 24, self.fontFlags end
function FrameMethods:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags end
function FrameMethods:EnableMouse(v) self.mouseEnabled = v and true or false end
function FrameMethods:IsMouseEnabled() return self.mouseEnabled == true end
function FrameMethods:SetDuration(d) self.duration = d end
function FrameMethods:GetDuration() return self.duration end
function FrameMethods:GetParent() return self.parent end
function FrameMethods:GetName() return self.name end
function FrameMethods:GetObjectType() return self.kind end
function FrameMethods:SetSize(w, h) self.width, self.height = w, h end
function FrameMethods:SetWidth(w) self.width = w end
function FrameMethods:SetHeight(h) self.height = h end
function FrameMethods:GetWidth() return self.width end
function FrameMethods:GetHeight() return self.height end
function FrameMethods:GetSize() return self.width, self.height end
function FrameMethods:GetCenter() return 0, 0 end
function FrameMethods:GetEffectiveScale() return 1 end
function FrameMethods:GetScale() return 1 end
function FrameMethods:GetVertexColor() return 1, 1, 1, 1 end
function FrameMethods:SetAlpha(a) self.alpha = a end
function FrameMethods:GetAlpha() return self.alpha end
function FrameMethods:IsVisible() return self.shown end
function FrameMethods:IsMouseOver() return false end
function FrameMethods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FrameMethods:ClearAllPoints() self.points = {} end
function FrameMethods:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
function FrameMethods:GetNumPoints() return #self.points end
function FrameMethods:SetMovable(v) self.movable = v end
function FrameMethods:IsMovable() return self.movable end
function FrameMethods:HookScript(script, fn)
	local previous = self.scripts[script]
	self.scripts[script] = function(...)
		if previous then previous(...) end
		return fn(...)
	end
end
-- Tooltip-like recording (GameTooltip, LibDBIcon's tooltip, ...)
function FrameMethods:ClearLines() self.lines = {} end
function FrameMethods:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
function FrameMethods:AddDoubleLine(left, right) self:AddLine(tostring(left) .. " | " .. tostring(right)) end
function FrameMethods:NumLines() return self.lines and #self.lines or 0 end
-- Test helper: simulate a click (OnClick script with the mouse button)
function FrameMethods:Click(button) local fn = self.scripts.OnClick; if fn then fn(self, button or "LeftButton", false) end end

-- Every widget object: frames, textures, font strings, animations. Unknown
-- methods are harmless no-ops; Create* methods create child objects.
local function makeObject(mock, kind, name, parent)
	local object = {
		mock = mock, kind = kind, name = name, parent = parent, children = {},
		events = {}, scripts = {}, shown = true, width = 100, height = 100, alpha = 1, points = {},
	}
	if parent and parent.children then
		parent.children[#parent.children + 1] = object
	end
	return setmetatable(object, {
		__index = function(_, key)
			if FrameMethods[key] then
				return FrameMethods[key]
			end
			if type(key) == "string" and key:find("^Create") then
				return function(self, childKind, childName)
					local child = makeObject(mock, key:sub(7), childName, self)
					child.childKind = childKind
					return child
				end
			end
			-- Widget methods are CamelCase; unknown ones are harmless no-ops.
			-- Unknown lowercase keys are data fields and read as nil, like on
			-- real widgets (libraries test them, e.g. button.minimapPos).
			if type(key) == "string" and key:find("^%u") then
				return function() end
			end
			return nil
		end,
	})
end
Mock.makeObject = makeObject

----------------------------------------------------------------------
-- Client
----------------------------------------------------------------------

function Mock.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Mock)
	self.now = 1000
	self.epoch = 1760000000
	self.startNow = self.now
	self.timers = {}
	self.timerSeq = 0
	self.frames = {}
	self.sent = {}       -- every SendAddonMessage call that was accepted
	self.refused = {}    -- calls refused with a result code
	self.received = {}   -- CHAT_MSG_ADDON deliveries to this client
	self.chat = {}       -- DEFAULT_CHAT_FRAME lines
	self.printed = {}
	self.sounds = {}     -- PlaySound calls
	self.errors = {}
	self.prefixes = {}
	self.invalidEvents = opts.invalidEvents or {}
	self.player = {
		name = opts.name or "Me",
		realm = opts.realm or "TestRealm",
		class = opts.class or "HUNTER",
		level = opts.level or 10,
		dead = false,
	}
	self.group = {}         -- others: { name, realm?, class }
	self.raid = false
	self.instanceGroup = false
	self.lockdown = false   -- C_ChatInfo.InChatMessagingLockdown()
	self.refuseSends = false -- SendAddonMessage returns AddOnMessageLockdown although not in lockdown
	self.encounter = false
	self.echoGroup = true
	self.zone = "Elwynn Forest"
	self.instance = { inInstance = false, type = "none", name = "Eastern Kingdoms", id = 0 }
	self.mirror = {}
	self.subzone = "Goldshire"
	self.money = 10000
	self.swimming, self.flying, self.falling = false, false, false
	self.spellNames = {
		[433] = "Food", [430] = "Drink", [8690] = "Hearthstone",
		[2366] = "Herb Gathering", [2575] = "Mining", [8613] = "Skinning",
	}
	self.taxiNodes = {}
	self.invoices = {}
	self.itemQuality = {}
	self.lootSource = {}
	self.lootSlots = { { isQuestItem = false } } -- GetLootSlotInfo per slot
	self.fishing = false
	self.professions = { indices = { 1, 2 }, names = { "Mining", "Herbalism" } }
	self.faction = "Alliance"
	self.scores = {}
	self.friendList = {} -- C_FriendList.GetFriendInfo(name) results
	self.honor, self.honorLevel = 100, 1
	self.metadata = { Version = opts.version or "@project-version@" }
	self.loggedIn = false
	self.errorHandler = function(err)
		self.errors[#self.errors + 1] = tostring(err)
		return err
	end
	Mock.NewNetwork():Add(self)
	self.env = self:BuildEnv()
	return self
end

function Mock:FullName()
	return self.player.name .. "-" .. self.player.realm
end

function Mock:MatchesName(target)
	return target == self.player.name or target == self:FullName()
end

function Mock:Unit(unit)
	if unit == "player" then
		return self.player, true
	end
	local index = unit:match("^party(%d+)$")
	if index and not self.raid then
		return self.group[tonumber(index)]
	end
	index = unit:match("^raid(%d+)$")
	if index and self.raid then
		index = tonumber(index)
		if index == 1 then
			return self.player, true
		end
		return self.group[index - 1]
	end
	return nil
end

-- Timers --------------------------------------------------------------

function Mock:AddTimer(delay, fn)
	self.timerSeq = self.timerSeq + 1
	self.timers[#self.timers + 1] = { at = self.now + math.max(delay or 0, 0), fn = fn, seq = self.timerSeq }
end

function Mock:RunTimers()
	while true do
		local bestIndex, best
		for i, timer in ipairs(self.timers) do
			if timer.at <= self.now + 1e-9 and (not best or timer.at < best.at or (timer.at == best.at and timer.seq < best.seq)) then
				bestIndex, best = i, timer
			end
		end
		if not best then
			return
		end
		table.remove(self.timers, bestIndex)
		best.fn()
	end
end

function Mock:RunOnUpdate(dt)
	local snapshot = {}
	for i, frame in ipairs(self.frames) do
		snapshot[i] = frame
	end
	for _, frame in ipairs(snapshot) do
		local onUpdate = frame.scripts.OnUpdate
		if onUpdate and frame.shown then
			onUpdate(frame, dt)
		end
	end
end

function Mock:Step(dt)
	self.now = self.now + dt
	self:RunTimers()
	self:RunOnUpdate(dt)
end

function Mock:Advance(seconds)
	self.net:Advance(seconds)
end

-- Events --------------------------------------------------------------

function Mock:Fire(event, ...)
	local snapshot = {}
	for i, frame in ipairs(self.frames) do
		snapshot[i] = frame
	end
	for _, frame in ipairs(snapshot) do
		local onEvent = frame.scripts.OnEvent
		if onEvent and frame.events[event] then
			onEvent(frame, event, ...)
		end
	end
end

function Mock:CreateFrame(frameType, name, parent)
	local frame = makeObject(self, frameType, name, parent)
	self.frames[#self.frames + 1] = frame
	if name then
		self.env[name] = frame
	end
	return frame
end

-- Scenario helpers ----------------------------------------------------

function Mock:JoinGroup(members, raid)
	self.group = members
	self.raid = raid or false
	self:Fire("GROUP_ROSTER_UPDATE")
end

function Mock:LeaveGroup()
	self.group = {}
	self.raid = false
	self:Fire("GROUP_ROSTER_UPDATE")
end

function Mock:StartEncounter(name)
	self.encounter = true
	self.lockdown = true
	self:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 2)
	self:Fire("ENCOUNTER_START", 1234, name or "Hogger", 1, 5)
end

function Mock:EndEncounter(success)
	self.encounter = false
	self.lockdown = false
	self:Fire("ENCOUNTER_END", 1234, "Hogger", 1, 5, success == false and 0 or 1)
	self:Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
end

function Mock:EnterInstance(name, instanceType, id)
	self.instance = { inInstance = true, type = instanceType or "party", name = name, id = id or 36 }
	self:Fire("PLAYER_ENTERING_WORLD", false, false)
end

function Mock:LeaveInstance()
	self.instance = { inInstance = false, type = "none", name = "Eastern Kingdoms", id = 0 }
	self:Fire("PLAYER_ENTERING_WORLD", false, false)
end

function Mock:ChatContains(fragment)
	for _, line in ipairs(self.chat) do
		if line:find(fragment, 1, true) then
			return true
		end
	end
	return false
end

-- Environment ---------------------------------------------------------

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

local function strsplit(delimiter, text, pieces)
	local out, start = {}, 1
	while true do
		if pieces and #out == pieces - 1 then
			out[#out + 1] = text:sub(start)
			break
		end
		local i, j = text:find(delimiter, start, true)
		if not i then
			out[#out + 1] = text:sub(start)
			break
		end
		out[#out + 1] = text:sub(start, i - 1)
		start = j + 1
	end
	return unpack(out)
end

function Mock:BuildEnv()
	local mock = self
	local G = {}
	local env = setmetatable({}, {
		__index = function(_, key)
			return G[key] -- unknown globals are nil, like in the game
		end,
	})

	-- Lua standard library as WoW exposes it (no io/os/require/dofile)
	for _, name in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset",
		"select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "loadstring",
		"collectgarbage", "_VERSION" }) do
		G[name] = _G[name]
	end
	G.coroutine = coroutine
	G.string = string
	G.math = math
	G.table = copy(table)
	G.table.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	G.wipe = G.table.wipe
	G.tinsert, G.tremove, G.sort = table.insert, table.remove, table.sort
	G.format, G.gsub, G.strfind, G.strmatch, G.strsub = string.format, string.gsub, string.find, string.match, string.sub
	G.strlen, G.strlower, G.strupper, G.strbyte, G.strchar, G.strrep = string.len, string.lower, string.upper, string.byte, string.char, string.rep
	G.floor, G.ceil, G.max, G.min, G.abs = math.floor, math.ceil, math.max, math.min, math.abs
	G.strsplit = strsplit
	G.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	G.strjoin = function(delimiter, ...)
		return table.concat({ ... }, delimiter)
	end
	G.date = os.date
	G.time = function(dateTable)
		if dateTable then
			return os.time(dateTable) -- like WoW: local time table -> timestamp
		end
		return mock.epoch + math.floor(mock.now - mock.startNow)
	end
	G.GetServerTime = G.time
	G.GetTime = function()
		return mock.now
	end
	G.GetFramerate = function()
		return 60
	end
	G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		mock.printed[#mock.printed + 1] = table.concat(parts, " ")
	end
	G.debugstack = function()
		return ""
	end

	-- WoW's xpcall passes extra arguments (Lua 5.2 style); 5.1's does not.
	G.xpcall = function(fn, handler, ...)
		local n = select("#", ...)
		if n == 0 then
			return xpcall(fn, handler)
		end
		local args = { ... }
		return xpcall(function()
			return fn(unpack(args, 1, n))
		end, handler)
	end
	G.geterrorhandler = function()
		return mock.errorHandler
	end
	G.seterrorhandler = function(fn)
		mock.errorHandler = fn
	end
	G.securecallfunction = function(fn, ...)
		return select(2, G.xpcall(fn, function(err)
			return mock.errorHandler(err)
		end, ...))
	end
	G.hooksecurefunc = function(a, b, c)
		local tbl, name, hook = a, b, c
		if type(a) == "string" then
			tbl, name, hook = env, a, b
		end
		local original = tbl[name]
		tbl[name] = function(...)
			local results = { n = 0 }
			local function pack(...)
				results.n = select("#", ...)
				for i = 1, results.n do
					results[i] = (select(i, ...))
				end
			end
			pack(original(...))
			hook(...)
			return unpack(results, 1, results.n)
		end
	end

	-- Secrets
	G.issecretvalue = isSecret

	-- Frames and UI
	G.CreateFrame = function(frameType, name, parent)
		return mock:CreateFrame(frameType, name, parent)
	end
	G.UIParent = makeObject(mock, "Frame", "UIParent")
	G.UIParent:SetSize(1920, 1080)
	G.Minimap = makeObject(mock, "Frame", "Minimap", G.UIParent)
	G.Minimap:SetSize(140, 140)
	G.GameTooltip = makeObject(mock, "GameTooltip", "GameTooltip", G.UIParent)
	G.GetCursorPosition = function()
		return 0, 0
	end
	G.UISpecialFrames = {}

	-- Settings API (signatures as in Blizzard_Settings.lua, Forever 1.60.1)
	mock.settings = { categories = {}, byVariable = {}, opened = nil }
	G.Settings = {
		VarType = { Boolean = "boolean", Number = "number" },
		RegisterVerticalLayoutCategory = function(name)
			local layout = { initializers = {} }
			function layout:AddInitializer(initializer)
				self.initializers[#self.initializers + 1] = initializer
			end
			local category = { name = name, layout = layout }
			function category:GetID()
				return 4242
			end
			mock.settings.categories[#mock.settings.categories + 1] = category
			return category, layout
		end,
		RegisterProxySetting = function(_, variable, varType, name, default, getValue, setValue)
			local setting = { variable = variable, varType = varType, name = name, default = default }
			function setting:GetValue()
				return getValue()
			end
			function setting:SetValue(value)
				setValue(value)
			end
			mock.settings.byVariable[variable] = setting
			return setting
		end,
		CreateCheckbox = function(category, setting, tooltip)
			local init = { kind = "checkbox", setting = setting, tooltip = tooltip }
			category.layout:AddInitializer(init)
			return init
		end,
		CreateSlider = function(category, setting, options, tooltip)
			local init = { kind = "slider", setting = setting, options = options, tooltip = tooltip }
			category.layout:AddInitializer(init)
			return init
		end,
		CreateSliderOptions = function(minValue, maxValue, rate)
			local options = { minValue = minValue, maxValue = maxValue, rate = rate }
			function options:SetLabelFormatter(_, formatter)
				self.formatter = formatter
			end
			return options
		end,
		RegisterAddOnCategory = function(category)
			mock.settings.registered = category
		end,
		OpenToCategory = function(categoryID)
			mock.settings.opened = categoryID
		end,
	}
	G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
		return { kind = "button", name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip }
	end
	G.CreateSettingsListSectionHeaderInitializer = function(name)
		return { kind = "header", name = name }
	end
	G.MinimalSliderWithSteppersMixin = { Label = { Right = 4 } }
	G.StaticPopupDialogs = {}
	mock.popups = {}
	G.StaticPopup_Show = function(which)
		mock.popups[#mock.popups + 1] = which
		return {}
	end
	G.YES, G.NO = "Yes", "No"
	G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, text)
			mock.chat[#mock.chat + 1] = text
		end,
	}
	G.RAID_CLASS_COLORS = {}
	for class, colorStr in pairs(CLASS_COLORS) do
		G.RAID_CLASS_COLORS[class] = { colorStr = colorStr }
	end
	G.UNKNOWNOBJECT = "Unknown"
	G.PlaySound = function(id, channel)
		mock.sounds[#mock.sounds + 1] = { id = id, channel = channel }
	end
	G.SlashCmdList = {}

	-- Client / addon info
	G.GetBuildInfo = function()
		return "1.60.1", "70338", "Oct 1 2026", 16001
	end
	G.IsLoggedIn = function()
		return mock.loggedIn
	end
	G.C_AddOns = {
		GetAddOnMetadata = function(_, field)
			return mock.metadata[field]
		end,
	}
	G.C_EventUtils = {
		IsEventValid = function(event)
			return not mock.invalidEvents[event]
		end,
	}
	G.Enum = {
		SendAddonMessageResult = SEND_RESULT,
		AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
		AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
	}

	-- Timers
	G.C_Timer = {
		After = function(delay, fn)
			mock:AddTimer(delay, fn)
		end,
		NewTicker = function(interval, fn, iterations)
			local ticker = { cancelled = false }
			function ticker:Cancel()
				self.cancelled = true
			end
			function ticker:IsCancelled()
				return self.cancelled
			end
			local count = 0
			local function tick()
				if ticker.cancelled then
					return
				end
				count = count + 1
				fn(ticker)
				if not ticker.cancelled and (not iterations or count < iterations) then
					mock:AddTimer(interval, tick)
				end
			end
			mock:AddTimer(interval, tick)
			return ticker
		end,
	}

	-- Chat / addon messages
	local function refuseVisibleChat()
		error("LooserPiml must never send visible chat messages", 2)
	end
	G.SendChatMessage = refuseVisibleChat
	G.BNSendGameData = function() end
	G.C_BattleNet = {}
	G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(prefix)
			assert(#prefix <= 16, "prefix too long")
			mock.prefixes[prefix] = true
			return 0
		end,
		IsAddonMessagePrefixRegistered = function(prefix)
			return mock.prefixes[prefix] == true
		end,
		SendAddonMessage = function(prefix, text, chatType, target)
			assert(type(text) == "string", "message must be a string")
			assert(#text <= 255, "addon message longer than 255 bytes: " .. #text)
			assert(not text:find("\0", 1, true), "addon message contains NUL")
			assert(mock.prefixes[prefix], "prefix not registered: " .. tostring(prefix))
			local call = { prefix = prefix, text = text, chatType = chatType, target = target, at = mock.now }
			if mock.lockdown or mock.refuseSends then
				mock.refused[#mock.refused + 1] = call
				return SEND_RESULT.AddOnMessageLockdown
			end
			if chatType ~= "WHISPER" and #mock.group == 0 then
				mock.refused[#mock.refused + 1] = call
				return SEND_RESULT.NotInGroup
			end
			if chatType == "WHISPER" and mock:MatchesName(target) then
				-- Real Forever server behaviour: accepts the call, then rejects
				-- the whisper to yourself with a system message.
				mock.chat[#mock.chat + 1] = "No player named '" .. mock.player.name .. "' is currently playing."
				return SEND_RESULT.Success
			end
			mock.sent[#mock.sent + 1] = call
			mock.net.pending[#mock.net.pending + 1] = {
				from = mock, prefix = prefix, text = text, chatType = chatType, target = target,
			}
			return SEND_RESULT.Success
		end,
		SendAddonMessageLogged = function()
			error("SendAddonMessageLogged is not used by LooserPiml", 2)
		end,
		SendChatMessage = refuseVisibleChat,
		InChatMessagingLockdown = function()
			return mock.lockdown
		end,
	}
	G.Ambiguate = function(name, context)
		local short, realm = name:match("^([^%-]+)%-(.+)$")
		if short and realm == mock.player.realm and context ~= "mail" then
			return short
		end
		return name
	end

	-- Units and group
	G.LE_PARTY_CATEGORY_HOME = 1
	G.LE_PARTY_CATEGORY_INSTANCE = 2
	G.UnitName = function(unit)
		local u, isPlayer = mock:Unit(unit)
		if not u then
			return nil
		end
		if isPlayer then
			return u.name, nil
		end
		return u.name, u.realm
	end
	G.UnitExists = function(unit)
		return mock:Unit(unit) ~= nil
	end
	G.UnitClass = function(unit)
		local u = mock:Unit(unit)
		if not u then
			return nil
		end
		if isSecret(u.class) then
			return u.class, u.class
		end
		return u.class:sub(1, 1) .. u.class:sub(2):lower(), u.class
	end
	G.UnitLevel = function(unit)
		local u = mock:Unit(unit)
		return u and u.level or 0
	end
	G.UnitIsDeadOrGhost = function(unit)
		local u = mock:Unit(unit)
		return u and u.dead or false
	end
	G.GetRealmName = function()
		return mock.player.realm
	end
	G.GetNormalizedRealmName = function()
		return mock.player.realm
	end
	G.IsInGroup = function(category)
		if category == G.LE_PARTY_CATEGORY_INSTANCE then
			return mock.instanceGroup
		end
		return #mock.group > 0
	end
	G.IsInRaid = function()
		return mock.raid and #mock.group > 0
	end
	G.GetNumGroupMembers = function()
		return #mock.group > 0 and #mock.group + 1 or 0
	end
	G.GetNumSubgroupMembers = function()
		return #mock.group
	end

	-- World
	G.GetRealZoneText = function()
		return mock.zone
	end
	G.IsInInstance = function()
		return mock.instance.inInstance, mock.instance.type
	end
	G.GetInstanceInfo = function()
		local i = mock.instance
		return i.name, i.type, 0, "", 5, 0, false, i.id, 0, nil, false
	end
	G.IsEncounterInProgress = function()
		return mock.encounter
	end
	G.C_InstanceEncounter = {
		IsEncounterInProgress = function()
			return mock.encounter
		end,
	}
	G.GetMirrorTimerProgress = function(timer)
		return mock.mirror[timer] or 0
	end
	G.GetSubZoneText = function()
		return mock.subzone
	end
	G.GetMoney = function()
		return mock.money
	end
	G.IsSwimming = function()
		return mock.swimming
	end
	G.IsFlying = function()
		return mock.flying
	end
	G.IsFalling = function()
		return mock.falling
	end
	G.C_Spell = {
		GetSpellName = function(spellID)
			return mock.spellNames[spellID]
		end,
	}
	-- Plain functions the addon may post-hook (hooksecurefunc); calling them
	-- here just records the call.
	mock.calls = {}
	for _, name in ipairs({ "JumpOrAscendStart", "TakeTaxiNode", "RepairAllItems", "TakeInboxMoney", "AutoLootMailItem" }) do
		G[name] = function(...)
			mock.calls[#mock.calls + 1] = { name = name, args = { ... } }
		end
	end
	-- GlobalStrings (English client) used for parsing system messages
	G.LOOT_ITEM_SELF = "You receive loot: %s."
	G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
	G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
	G.LOOT_ITEM_CREATED_SELF = "You create: %s."
	G.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
	G.LOOT_ITEM = "%s receives loot: %s."
	G.SKILL_RANK_UP = "Your skill in %s has increased to %d."
	G.DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
	G.DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
	G.C_Item = {
		GetItemQualityByID = function(link)
			return mock.itemQuality[link]
		end,
	}
	G.GetLootSourceInfo = function(slot)
		return mock.lootSource[slot]
	end
	G.IsFishingLoot = function()
		return mock.fishing
	end
	G.GetNumLootItems = function()
		return #mock.lootSlots
	end
	-- texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin
	G.GetLootSlotInfo = function(slot)
		local s = mock.lootSlots[slot]
		if not s then
			return nil
		end
		return 133784, s.name or "Item", 1, nil, 1, false, s.isQuestItem == true, nil, false, false
	end
	G.GetProfessions = function()
		return unpack(mock.professions.indices)
	end
	G.GetProfessionInfo = function(index)
		return mock.professions.names[index]
	end
	G.UnitFactionGroup = function()
		return mock.faction
	end
	G.C_PvP = {
		GetScoreInfo = function(index)
			return mock.scores[index]
		end,
	}
	G.C_FriendList = {
		GetFriendInfo = function(name)
			return mock.friendList[name]
		end,
	}
	G.UnitHonor = function()
		return mock.honor
	end
	G.UnitHonorLevel = function()
		return mock.honorLevel
	end
	G.TaxiNodeName = function(index)
		return mock.taxiNodes[index]
	end
	G.GetInboxInvoiceInfo = function(index)
		return mock.invoices[index]
	end

	env._G = env
	self.G = G
	return env
end

return Mock
