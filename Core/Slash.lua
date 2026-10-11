-- /lp slash command. Modules add subcommands with ns.Slash:Register.
local _, ns = ...
local L = ns.L

local Slash = {}
ns:RegisterCore("Slash", Slash)

local commands = {} -- name -> { fn, usage, help }
local order = {}

function Slash:Register(name, fn, usage, help)
	if not commands[name] then
		order[#order + 1] = name
	end
	commands[name] = { fn = fn, usage = usage or "", help = help or "" }
end

function Slash:PrintHelp()
	ns.Log:Print(L.HELP_HEADER)
	for _, name in ipairs(order) do
		local cmd = commands[name]
		local usage = cmd.usage ~= "" and (" " .. cmd.usage) or ""
		ns.Log:Print("  /lp %s%s - %s", name, usage, cmd.help)
	end
end

function Slash:Dispatch(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "help" then
		self:PrintHelp()
		return
	end
	local entry = commands[cmd]
	if not entry then
		ns.Log:Print(L.SLASH_UNKNOWN, cmd)
		self:PrintHelp()
		return
	end
	entry.fn(rest or "")
end

local function parseOnOff(arg)
	arg = (arg or ""):lower()
	if arg == "on" or arg == "1" or arg == "true" then
		return true
	elseif arg == "off" or arg == "0" or arg == "false" then
		return false
	end
	return nil
end

function Slash:OnInitialize()
	self:Register("test", function(arg)
		local on = parseOnOff(arg)
		if on == true then
			ns.TestMode:Enable()
		elseif on == false then
			ns.TestMode:Disable()
		else
			ns.Log:Print(L.TEST_STATE, ns.TestMode:IsEnabled() and L.ON or L.OFF)
		end
	end, "on/off", L.HELP_TEST)

	self:Register("sim", function(arg)
		local kind, name = arg:match("^(%S*)%s*(%S*)")
		ns.TestMode:Sim(kind, name)
	end, "<event> [name]", L.HELP_SIM)

	self:Register("selftest", function()
		ns.TestMode:SelfTest()
	end, "", L.HELP_SELFTEST)

	self:Register("debug", function(arg)
		local on = parseOnOff(arg)
		if on ~= nil then
			ns.Log:SetDebug(on)
		end
		ns.Log:Print(L.DEBUG_STATE, ns.Log:IsDebug() and L.ON or L.OFF)
	end, "on/off", L.HELP_DEBUG)

	self:Register("version", function()
		ns.Version:PrintVersions()
	end, "", L.HELP_VERSION)

	self:Register("log", function(arg)
		ns.Log:PrintRecent(tonumber(arg))
	end, "[count]", L.HELP_LOG)

	SLASH_LOOSERPIML1 = "/lp"
	SLASH_LOOSERPIML2 = "/looserpiml"
	SlashCmdList.LOOSERPIML = function(input)
		Slash:Dispatch(input)
	end
end
