-- LooserPiml: namespace, module registry and lifecycle.
--
-- Core services (Events, DB, Log, Comm, ...) register with ns:RegisterCore and
-- are initialized in load order. Feature modules (Ticker, later Inventory,
-- Professions, Bets) are created with ns:NewModule and can be enabled or
-- disabled at runtime.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.core = {}        -- ordered list of core services
ns.modules = {}     -- name -> module
ns.moduleOrder = {} -- module names in registration order

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Midnight/Forever "secret values": an API may hand us a value we are not
-- allowed to inspect (compare, do math on, use as a key). We never try to
-- work around that; callers check with ns.IsSecret and drop the value.
function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function reportError(err)
	if ns.Log then
		ns.Log:CaptureError(err)
	end
	local handler = geterrorhandler and geterrorhandler()
	if handler then
		handler(err)
	end
	return err
end

-- Calls fn(...) without letting an error break the caller (e.g. the event
-- dispatcher). Errors still reach the normal error handler (BugSack etc.)
-- and our debug log. Returns ok, results...
-- WoW's xpcall forwards extra arguments to fn (Lua 5.2 style); stock Lua 5.1
-- doesn't, which is why the test mock polyfills it.
function ns.SafeCall(fn, ...)
	return xpcall(fn, reportError, ...)
end

----------------------------------------------------------------------
-- Core services
----------------------------------------------------------------------

function ns:RegisterCore(name, service)
	assert(type(name) == "string" and self[name] == nil, "core service name missing or taken: " .. tostring(name))
	service.name = name
	self[name] = service
	self.core[#self.core + 1] = service
	return service
end

----------------------------------------------------------------------
-- Modules
----------------------------------------------------------------------

local Module = {}
Module.__index = Module

function Module:IsEnabled()
	return self.enabled == true
end

-- defaultEnabled: whether the module starts enabled on a fresh install (default true)
function ns:NewModule(name, defaultEnabled)
	assert(type(name) == "string" and self.modules[name] == nil, "module name missing or taken: " .. tostring(name))
	local mod = setmetatable({
		name = name,
		enabled = false,
		defaultEnabled = defaultEnabled ~= false,
	}, Module)
	self.modules[name] = mod
	self.moduleOrder[#self.moduleOrder + 1] = name
	return mod
end

function ns:GetModule(name)
	return self.modules[name]
end

function ns:EnableModule(name)
	local mod = self.modules[name]
	if not mod or mod.enabled then
		return false
	end
	mod.enabled = true
	if mod.OnEnable then
		local ok = ns.SafeCall(mod.OnEnable, mod)
		if not ok then
			-- Half-enabled modules are worse than disabled ones.
			self:DisableModule(name)
			return false
		end
	end
	self.Log:Debug("Module %s enabled", name)
	return true
end

function ns:DisableModule(name)
	local mod = self.modules[name]
	if not mod or not mod.enabled then
		return false
	end
	mod.enabled = false
	if mod.OnDisable then
		ns.SafeCall(mod.OnDisable, mod)
	end
	-- Modules register with themselves as owner, so cleanup is automatic.
	self.Events:UnregisterAll(mod)
	self.Comm:UnregisterHandlers(mod)
	self.Log:Debug("Module %s disabled", name)
	return true
end

-- Persistent toggle (stored in SavedVariables)
function ns:SetModuleEnabled(name, enabled)
	self.DB:SetModuleEnabled(name, enabled)
	if enabled then
		return self:EnableModule(name)
	end
	return self:DisableModule(name)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

-- ADDON_LOADED: SavedVariables are available.
function ns:Initialize()
	if self.initialized then
		return
	end
	self.initialized = true
	for _, service in ipairs(self.core) do
		if service.OnInitialize then
			ns.SafeCall(service.OnInitialize, service)
		end
	end
	for _, name in ipairs(self.moduleOrder) do
		local mod = self.modules[name]
		if mod.OnInitialize then
			ns.SafeCall(mod.OnInitialize, mod)
		end
	end
end

-- PLAYER_LOGIN: the player and the world are available.
function ns:Enable()
	if self.loggedIn then
		return
	end
	self.loggedIn = true
	for _, service in ipairs(self.core) do
		if service.OnEnable then
			ns.SafeCall(service.OnEnable, service)
		end
	end
	for _, name in ipairs(self.moduleOrder) do
		if self.DB:IsModuleEnabled(name, self.modules[name].defaultEnabled) then
			self:EnableModule(name)
		end
	end
end

-- ADDON_LOADED fires once per addon, so filter by our name. The game loads our
-- SavedVariables right before our ADDON_LOADED. PLAYER_LOGIN fires after all
-- addons are loaded (also after every /reload); from then on player, realm
-- and group information can be trusted.
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		ns:Initialize()
		if IsLoggedIn and IsLoggedIn() then
			ns:Enable() -- loaded after login (load-on-demand)
		end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		ns:Enable()
	end
end)
