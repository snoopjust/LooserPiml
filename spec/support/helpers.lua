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

-- The communication rule, checked on every single SendAddonMessage call
-- of every test: only WHISPER (never PARTY/RAID/INSTANCE_CHAT/GUILD), only
-- to a listed LooserPiml friend, and nothing at all leaves the client in
-- test mode.
local function checkRecipients(mock, call)
	local ns = mock.ns
	if not (ns and ns.Friends and ns.DB and ns.DB.data) then
		return
	end
	local function violation(text)
		mock.violations[#mock.violations + 1] = text
	end
	if ns.TestMode:IsEnabled() then
		violation("sent a " .. tostring(call.chatType) .. " message in test mode")
	end
	if call.chatType ~= "WHISPER" then
		violation("sent on " .. tostring(call.chatType) .. " (only WHISPER to friends is allowed)")
	elseif not ns.Friends:IsListed(call.target) then
		violation("whispered " .. tostring(call.target) .. ", who is not on the friends list")
	end
end
H.checkRecipients = checkRecipients

-- Puts names on the client's LooserPiml friends list (as the friends UI
-- would, without the side effects).
function H.befriend(mock, names)
	local ns = mock.ns
	for _, name in ipairs(names) do
		ns.DB:Get("friends")[ns.Roster:Normalize(name)] = { added = 0 }
	end
end

-- Creates a client, loads the addon and runs the login sequence.
-- opts: name, realm, class, version, savedVariables, testMode, group, debug,
--       friends (names on the LooserPiml friends list from the start),
--       confirmed (friends who also answered the handshake, as if they had
--       listed us too)
function H.client(opts)
	opts = opts or {}
	local mock = Mock.new(opts)
	H.created[#H.created + 1] = mock
	mock.violations = {}
	mock.onSend = function(call)
		checkRecipients(mock, call)
	end
	if opts.savedVariables then
		mock.env.LooserPimlDB = opts.savedVariables
	end
	if opts.group then
		mock.group = opts.group
	end
	local ns = H.load(mock)

	mock:Fire("ADDON_LOADED", H.ADDON)
	if opts.friends then
		H.befriend(mock, opts.friends)
	end
	if opts.confirmed then
		H.befriend(mock, opts.confirmed)
	end
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
	for _, name in ipairs(opts.confirmed or {}) do
		H.confirm(mock, name)
	end
	return mock, ns
end

-- As if `name` (already on the list) had answered our handshake.
function H.confirm(mock, name)
	local ns = mock.ns
	ns.Friends:OnHandshake(ns.Roster:Normalize(name), "v0.2.0")
end

-- Several connected friends on a shared network, NOT grouped (the normal
-- case: everyone playing on their own). Each has the others on the WoW
-- friends list (online) and, unless a spec says otherwise
-- (friends = {...}), on the LooserPiml friends list.
-- specs: array of { name, class, ... } (the H.client opts)
function H.friends(specs)
	local net = Mock.NewNetwork()
	local clients = {}
	for i, spec in ipairs(specs) do
		local names = {}
		for j, other in ipairs(specs) do
			if i ~= j then
				names[#names + 1] = other.name
			end
		end
		if spec.friends == nil then
			spec.friends = names
		end
		spec.settle = 0
		local mock = H.client(spec)
		for _, name in ipairs(names) do
			mock.friendList[name] = { connected = true }
		end
		net:Add(mock)
		clients[#clients + 1] = mock
	end
	net:Advance(7) -- handshakes after login (5 s), stats after that
	return clients, net
end

-- Puts several clients into one group on a shared network. Unless a spec
-- says otherwise (friends = {...}), everyone has everyone else on their
-- LooserPiml friends list.
-- specs: array of { name, class, ... } (the H.client opts)
function H.group(specs)
	local net = Mock.NewNetwork()
	local clients = {}
	for i, spec in ipairs(specs) do
		local others, names = {}, {}
		for j, other in ipairs(specs) do
			if i ~= j then
				others[#others + 1] = { name = other.name, class = other.class or "WARRIOR" }
				names[#names + 1] = other.name
			end
		end
		spec.group = others
		if spec.friends == nil then
			spec.friends = names
		end
		spec.settle = 0
		local mock = H.client(spec)
		-- move from the private network to the shared one
		net:Add(mock)
		clients[#clients + 1] = mock
	end
	net:Advance(6) -- login HELLOs travel
	return clients, net
end

-- Every LooserPiml message a client handed to the network, decoded, with
-- AceComm's multi-part chunks put back together (per target, like
-- AceComm does on the receiving side): { t, d, chatType, target }.
function H.decodedSent(mock)
	local out, partial = {}, {}
	for _, call in ipairs(mock.sent) do
		if call.prefix == "LPiml" then
			local key = tostring(call.chatType) .. ":" .. tostring(call.target)
			local control, rest = call.text:match("^([\001-\009])(.*)$")
			local text
			if control == "\001" then
				partial[key] = { rest }
			elseif control == "\002" and partial[key] then
				table.insert(partial[key], rest)
			elseif control == "\003" and partial[key] then
				table.insert(partial[key], rest)
				text = table.concat(partial[key])
				partial[key] = nil
			elseif control == "\004" then
				text = rest
			elseif not control then
				text = call.text
			end
			if text then
				local envelope = mock.ns.Comm:Decode(text)
				if envelope then
					out[#out + 1] = { t = envelope.t, d = envelope.d, chatType = call.chatType, target = call.target }
				end
			end
		end
	end
	return out
end

-- All texts (SetText) of a widget tree that are currently shown, colors
-- stripped, in creation order. Hidden subtrees are skipped.
function H.texts(object, out)
	out = out or {}
	if not object or object.shown == false then
		return out
	end
	if object.text_ and object.text_ ~= "" then
		out[#out + 1] = H.stripColors(tostring(object.text_))
	end
	for _, child in ipairs(object.children or {}) do
		H.texts(child, out)
	end
	return out
end

function H.hasText(object, fragment)
	for _, text in ipairs(H.texts(object)) do
		if text:find(fragment, 1, true) then
			return true
		end
	end
	return false
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

-- Fails the test if the client ever sent to someone off its friends list,
-- or whispered someone who isn't online (the server answers that with a
-- "No player named ..." line).
function H.assertRecipientsOk(mock)
	if #mock.violations > 0 then
		error("Communication rule broken by " .. mock.player.name .. ":\n" .. table.concat(mock.violations, "\n"), 2)
	end
	if not mock.allowNotFound then
		for _, line in ipairs(mock.chat) do
			if line:find("is currently playing", 1, true) then
				error(mock.player.name .. " whispered someone who is offline: " .. line, 2)
			end
		end
	end
end

-- Fails the test if the addon itself called a duel action (StartDuel,
-- AcceptDuel, CancelDuel, ForfeitDuel) or hid / clicked Blizzard's duel
-- dialog. Only the player may do that (Mock:UserAction).
function H.assertNoGameActions(mock)
	if #mock.gameActions > 0 then
		error(mock.player.name .. "'s LooserPiml performed game actions: " .. table.concat(mock.gameActions, ", "), 2)
	end
end

-- Used in after_each: every client created during the test must be
-- error-free, must have kept the communication rule and must never have
-- acted for the player.
function H.checkClients()
	local created = H.created
	H.created = {}
	for _, mock in ipairs(created) do
		H.assertNoErrors(mock)
		H.assertRecipientsOk(mock)
		H.assertNoGameActions(mock)
	end
end

return H
