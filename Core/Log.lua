-- Debug logging plus capture of anything the client restricted.
--
-- Everything goes into a small ring buffer (/lp log). What is printed:
--   Print: always (normal user-facing output)
--   Debug: only in debug mode
--   Warn / blocked actions / Lua errors: in debug or test mode
--
-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN / LUA_WARNING are always
-- recorded, so a restriction hit shows up immediately while testing.
local ADDON_NAME, ns = ...
local L = ns.L

local Log = {}
ns:RegisterCore("Log", Log)

Log.MAX_ENTRIES = 200
Log.entries = {}
Log.counts = { blocked = 0, forbidden = 0, errors = 0, warnings = 0 }

local function chat(msg)
	local chatFrame = DEFAULT_CHAT_FRAME
	if chatFrame then
		chatFrame:AddMessage(L.ADDON_PREFIX .. ": " .. msg)
	end
end

local function render(msg, ...)
	if select("#", ...) == 0 then
		return tostring(msg)
	end
	local ok, text = pcall(string.format, msg, ...)
	return ok and text or tostring(msg)
end

local function record(level, text)
	local entries = Log.entries
	entries[#entries + 1] = string.format("%s [%s] %s", date("%H:%M:%S"), level, text)
	if #entries > Log.MAX_ENTRIES then
		table.remove(entries, 1)
	end
end

function Log:IsDebug()
	return ns.DB:Get("debug") == true
end

-- Debug or test mode: show warnings, blocked actions and errors.
function Log:IsVerbose()
	return self:IsDebug() or (ns.TestMode ~= nil and ns.TestMode:IsEnabled())
end

function Log:Print(msg, ...)
	local text = render(msg, ...)
	record("info", text)
	chat(text)
end

function Log:Debug(msg, ...)
	local text = render(msg, ...)
	record("debug", text)
	if self:IsDebug() then
		chat("|cff999999[debug]|r " .. text)
	end
end

function Log:Warn(msg, ...)
	local text = render(msg, ...)
	self.counts.warnings = self.counts.warnings + 1
	record("warn", text)
	if self:IsVerbose() then
		chat("|cffffaa00[warn]|r " .. text)
	end
end

function Log:CaptureError(err)
	local text = tostring(err)
	-- The same error twice in a row (e.g. once from SafeCall, once from the
	-- error-handler hook, or a handler failing on every event) is logged once.
	if text == self.lastError then
		return
	end
	self.lastError = text
	self.counts.errors = self.counts.errors + 1
	record("error", text)
	if self:IsVerbose() then
		chat("|cffff3333[Lua error]|r " .. text)
	end
end

----------------------------------------------------------------------
-- Restriction events
----------------------------------------------------------------------

-- ADDON_ACTION_BLOCKED: a protected function was called from tainted code
-- (typically in combat). ADDON_ACTION_FORBIDDEN: a function addons may never
-- call. Both carry (blamedAddon, functionName). The game only shows a vague
-- "action blocked by an addon" message, so we record the function name.
-- LooserPiml calls no protected functions; any hit here is a bug to report.
local function isOurs(addon)
	return addon == ADDON_NAME
end

function Log:ADDON_ACTION_BLOCKED(_, addon, func)
	addon, func = tostring(addon), tostring(func)
	self.counts.blocked = self.counts.blocked + 1
	local text = L.BLOCKED_ACTION:format(addon, func)
	record("blocked", text)
	if isOurs(addon) and self:IsVerbose() then
		chat("|cffff3333" .. text .. "|r")
	end
end

function Log:ADDON_ACTION_FORBIDDEN(_, addon, func)
	addon, func = tostring(addon), tostring(func)
	self.counts.forbidden = self.counts.forbidden + 1
	local text = L.FORBIDDEN_ACTION:format(addon, func)
	record("forbidden", text)
	if isOurs(addon) and self:IsVerbose() then
		chat("|cffff3333" .. text .. "|r")
	end
end

function Log:LUA_WARNING(_, ...)
	-- Payload differs between clients; log every string argument.
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "string" and not ns.IsSecret(value) then
			parts[#parts + 1] = value
		end
	end
	local text = table.concat(parts, " ")
	if text:find(ADDON_NAME, 1, true) then
		self:Warn("Lua warning: %s", text)
	else
		record("luawarning", text)
	end
end

----------------------------------------------------------------------
-- Error handler hook (debug/test mode only)
----------------------------------------------------------------------
-- Catches our Lua errors that don't pass through ns.SafeCall (e.g. frame
-- scripts). There is only one error handler for the whole UI, shared by all
-- addons, so it is installed only after debug or test mode is switched on,
-- and the previous handler (Blizzard's, BugSack's, ...) is always called.

function Log:InstallErrorHook()
	if self.errorHookInstalled or not (geterrorhandler and seterrorhandler) then
		return
	end
	local previous = geterrorhandler()
	seterrorhandler(function(msg, ...)
		if self:IsVerbose() and type(msg) == "string" and msg:find(ADDON_NAME, 1, true) then
			self:CaptureError(msg)
		end
		if previous then
			return previous(msg, ...)
		end
	end)
	self.errorHookInstalled = true
end

function Log:SetDebug(enabled)
	ns.DB:Set("debug", enabled and true or false)
	if enabled then
		self:InstallErrorHook()
	end
end

function Log:PrintRecent(count)
	count = count or 20
	local entries = self.entries
	if #entries == 0 then
		self:Print(L.LOG_EMPTY)
		return
	end
	local first = math.max(1, #entries - count + 1)
	chat(L.LOG_HEADER:format(#entries - first + 1))
	for i = first, #entries do
		chat("  " .. entries[i])
	end
end

function Log:OnInitialize()
	ns.Events:Register(self, "ADDON_ACTION_BLOCKED")
	ns.Events:Register(self, "ADDON_ACTION_FORBIDDEN")
	ns.Events:Register(self, "LUA_WARNING")
	if self:IsDebug() then
		self:InstallErrorHook()
	end
end
