-- Test helpers: load the addon exactly as the .toc lists it (libraries
-- included) into a mock client, and boot it like the game would.
local Mock = require("wow_mock")

local H = {}
H.Mock = Mock
H.ADDON = "LooserPiml"

local function readFile(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

local function dirname(path)
	return path:match("^(.*)/[^/]*$") or "."
end

local function expandXml(path, out)
	local content = assert(readFile(path), "missing file: " .. path)
	local base = dirname(path)
	for tag, file in content:gmatch("<(%a+)%s+file%s*=%s*\"([^\"]+)\"") do
		local child = base .. "/" .. file:gsub("\\", "/")
		if tag == "Include" then
			expandXml(child, out)
		elseif tag == "Script" then
			out[#out + 1] = child
		end
	end
end

-- Files in .toc order, XML includes expanded.
function H.tocFiles()
	local toc = assert(readFile(H.ADDON .. ".toc"), "run the tests from the repository root")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and not line:find("^#") then
			local path = line:gsub("\\", "/")
			if path:find("%.xml$") then
				expandXml(path, files)
			else
				files[#files + 1] = path
			end
		end
	end
	return files
end

local cachedChunks = {}

local function loadChunk(path)
	if not cachedChunks[path] then
		if not readFile(path) then
			error("missing file " .. path .. (path:find("^Libs/") and " - run tools/fetch-libs.ps1 first" or ""))
		end
		cachedChunks[path] = assert(loadfile(path))
	end
	-- string.dump + loadstring gives a fresh function we can setfenv safely
	return assert(loadstring(string.dump(cachedChunks[path]), "@" .. path))
end

-- Loads all addon files into the mock's environment. Returns the namespace.
function H.load(mock)
	local ns = {}
	for _, path in ipairs(H.tocFiles()) do
		local chunk = loadChunk(path)
		setfenv(chunk, mock.env)
		chunk(H.ADDON, ns)
	end
	mock.ns = ns
	return ns
end

H.created = {}

-- Creates a client, loads the addon and runs the login sequence.
-- opts: name, realm, class, version, savedVariables, testMode, group, debug
function H.client(opts)
	opts = opts or {}
	local mock = Mock.new(opts)
	H.created[#H.created + 1] = mock
	if opts.savedVariables then
		mock.env.LooserPimlDB = opts.savedVariables
	end
	if opts.group then
		mock.group = opts.group
	end
	local ns = H.load(mock)

	mock:Fire("ADDON_LOADED", H.ADDON)
	mock.loggedIn = true
	mock:Fire("PLAYER_LOGIN")
	mock:Fire("PLAYER_ENTERING_WORLD", true, false)

	-- Deterministic banner text and a record of what was rendered.
	local ticker = ns:GetModule("Ticker")
	local display = ticker.Display
	display.Pick = function()
		return 1
	end
	mock.rendered = {}
	local render = display.Render
	display.Render = function(self, text, ...)
		mock.rendered[#mock.rendered + 1] = text
		return render(self, text, ...)
	end

	if opts.debug then
		ns.Log:SetDebug(true)
	end
	if opts.testMode then
		ns.TestMode:Enable()
	end
	-- Let login timers (HELLO etc.) run.
	mock:Advance(opts.settle or 6)
	return mock, ns
end

-- Puts several clients into one group on a shared network.
-- specs: array of { name, class, ... } (the H.client opts)
function H.group(specs)
	local net = Mock.NewNetwork()
	local clients = {}
	for i, spec in ipairs(specs) do
		local others = {}
		for j, other in ipairs(specs) do
			if i ~= j then
				others[#others + 1] = { name = other.name, class = other.class or "WARRIOR" }
			end
		end
		spec.group = others
		spec.settle = 0
		local mock = H.client(spec)
		-- move from the private network to the shared one
		net:Add(mock)
		clients[#clients + 1] = mock
	end
	net:Advance(6) -- login HELLOs travel
	return clients, net
end

-- Removes color codes and texture escapes, trims, collapses double spaces.
function H.stripColors(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("  +", " "))
end

function H.lastRendered(mock)
	return mock.rendered[#mock.rendered] and H.stripColors(mock.rendered[#mock.rendered])
end

function H.renderedPlain(mock)
	local out = {}
	for i, text in ipairs(mock.rendered) do
		out[i] = H.stripColors(text)
	end
	return out
end

-- Fails the test if any Lua error reached the error handler.
function H.assertNoErrors(mock)
	if #mock.errors > 0 then
		error("Lua errors in client " .. mock.player.name .. ":\n" .. table.concat(mock.errors, "\n"), 2)
	end
end

-- Used in after_each: every client created during the test must be error-free.
function H.checkClients()
	local created = H.created
	H.created = {}
	for _, mock in ipairs(created) do
		H.assertNoErrors(mock)
	end
end

return H
