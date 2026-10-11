-- Test mode and self-test, so everything can be tried solo on one account.
--
-- /lp test on   loopback: outgoing messages never leave the client, fake
--               group members appear (one with an outdated version)
-- /lp sim ...   simulate events; modules register their own simulations
-- /lp selftest  libraries, encoding, loopback and the REAL transport
--               (a hidden addon message whispered to yourself)
local _, ns = ...
local L = ns.L

local TestMode = {}
ns:RegisterCore("TestMode", TestMode)

TestMode.FAKE_MEMBERS = {
	{ name = "Max", class = "WARRIOR", version = "same" },
	{ name = "Lena", class = "MAGE", version = "same" },
	{ name = "Jo", class = "PRIEST", version = "newer" },
	{ name = "Kim", class = "ROGUE", version = "older" },
}
TestMode.BOSS_DURATION = 10      -- seconds of a simulated encounter
TestMode.SELFTEST_TIMEOUT = 10   -- seconds to wait for our own whisper
TestMode.SELFTEST_SIZE = 1200    -- payload chars, enough for several chunks

TestMode.enabled = false
local sims = {}     -- kind -> { owner, fn }
local simOrder = {}

function TestMode:IsEnabled()
	return self.enabled
end

local function fakeVersion(kind)
	local base = ns.Version:GetComparable() or ns.Version.TEST_BASELINE
	local v = ns.Version.Parse(base) or { 1, 0, 0 }
	if kind == "older" then
		if v[3] > 0 then
			return string.format("%d.%d.%d", v[1], v[2], v[3] - 1)
		elseif v[2] > 0 then
			return string.format("%d.%d.0", v[1], v[2] - 1)
		end
		return "0.9.0"
	elseif kind == "newer" then
		return string.format("%d.%d.0", v[1], v[2] + 1)
	end
	return base
end

function TestMode:Enable()
	if self.enabled then
		return
	end
	self.enabled = true
	ns.Log:InstallErrorHook()
	ns.Roster:SetFakeMembers(self.FAKE_MEMBERS)
	local names = {}
	for _, member in ipairs(self.FAKE_MEMBERS) do
		names[#names + 1] = ns.Roster:ColorName(member.name, member.class)
	end
	ns.Log:Print(L.TEST_ON, table.concat(names, ", "))
	-- The fake group says hello, like a real group would after a join.
	C_Timer.After(1, function()
		if not self.enabled then
			return
		end
		for _, member in ipairs(self.FAKE_MEMBERS) do
			ns.Comm:SimulateReceive(member.name, ns.Version.MSG, {
				ver = fakeVersion(member.version),
				proto = ns.Comm.PROTOCOL,
				reply = true,
			})
		end
	end)
end

function TestMode:Disable()
	if not self.enabled then
		return
	end
	ns.Events:SetSimulatedEncounter(false)
	self.enabled = false
	ns.Roster:SetFakeMembers(nil)
	ns.Version.warned = {}
	ns.Log:Print(L.TEST_OFF)
end

----------------------------------------------------------------------
-- Simulations
----------------------------------------------------------------------

-- fn(owner, kind, name) - name is nil for "the player"
function TestMode:RegisterSim(owner, kinds, fn)
	for _, kind in ipairs(kinds) do
		if not sims[kind] then
			simOrder[#simOrder + 1] = kind
		end
		sims[kind] = { owner = owner, fn = fn }
	end
end

function TestMode:GetSimKinds()
	local kinds = { "boss" }
	for _, kind in ipairs(simOrder) do
		kinds[#kinds + 1] = kind
	end
	return kinds
end

local ALIASES = {
	died = "death", die = "death", dead = "death",
	drowned = "drown",
	level = "levelup", lvl = "levelup", ding = "levelup",
	dungeon = "enter", join = "enter", exit = "leave",
	encounter = "boss",
}

-- Returns true if something was simulated.
function TestMode:Sim(kind, name)
	if not self.enabled then
		ns.Log:Print(L.SIM_NEEDS_TEST)
		return false
	end
	kind = kind and kind:lower() or ""
	kind = ALIASES[kind] or kind
	if name == "" then
		name = nil
	end
	if name then
		-- Letters only: the name ends up in banners and chat.
		name = name:gsub("[^%a]", "")
		name = name:sub(1, 1):upper() .. name:sub(2):lower()
		if name == "" or ns.Roster:IsPlayer(name) then
			name = nil
		end
	end
	if kind == "boss" then
		self:SimEncounter()
		return true
	end
	local sim = sims[kind]
	if not sim then
		ns.Log:Print(L.SIM_USAGE, table.concat(self:GetSimKinds(), "/"))
		return false
	end
	ns.SafeCall(sim.fn, sim.owner, kind, name)
	return true
end

-- A fake boss fight: events during it are held, then shown afterwards.
function TestMode:SimEncounter()
	ns.Events:SetSimulatedEncounter(true, L.SIM_BOSS_NAME)
	ns.Log:Print(L.SIM_BOSS_START, self.BOSS_DURATION)
	local fake = self.FAKE_MEMBERS[1].name
	C_Timer.After(2, function()
		self:Sim("death", fake)
	end)
	C_Timer.After(4, function()
		self:Sim("death")
	end)
	C_Timer.After(self.BOSS_DURATION, function()
		ns.Events:SetSimulatedEncounter(false)
		ns.Log:Print(L.SIM_BOSS_END)
	end)
end

----------------------------------------------------------------------
-- Self-test
----------------------------------------------------------------------

local function result(ok, text)
	ns.Log:Print(ok and L.SELFTEST_OK or L.SELFTEST_FAIL, text)
end

local function info(text)
	ns.Log:Print(L.SELFTEST_INFO, text)
end

-- Deterministic, poorly compressible text, so the payload needs several chunks.
local function makePayload(size)
	local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/"
	local chars, x = {}, 12345
	for i = 1, size do
		x = (x * 1103515245 + 12345) % 2147483648
		local index = math.floor(x / 65536) % #alphabet + 1
		chars[i] = alphabet:sub(index, index)
	end
	return table.concat(chars)
end

local function checksum(text)
	local sum = 0
	for i = 1, #text do
		sum = (sum * 31 + text:byte(i)) % 2147483647
	end
	return sum
end

local function yesNo(value)
	return value and "yes" or "NO"
end

function TestMode:SelfTest()
	ns.Log:Print(L.SELFTEST_HEADER)

	-- 1. Libraries
	local libs, missing = {}, {}
	for _, lib in ipairs({ "CallbackHandler-1.0", "AceComm-3.0", "AceSerializer-3.0", "LibDeflate" }) do
		local _, minor = LibStub:GetLibrary(lib, true)
		if minor then
			libs[#libs + 1] = lib .. " r" .. tostring(minor)
		else
			missing[#missing + 1] = lib
		end
	end
	if #missing > 0 then
		result(false, L.SELFTEST_LIBS_MISSING:format(table.concat(missing, ", ")))
	else
		result(true, L.SELFTEST_LIBS:format(table.concat(libs, ", ")))
	end

	-- 2. Encoding roundtrip
	local payload = makePayload(self.SELFTEST_SIZE)
	local envelope = { v = ns.Comm.PROTOCOL, t = "SELFTEST", d = { text = payload, n = 42, flag = true } }
	local encoded = ns.Comm:Encode(envelope)
	local decoded = ns.Comm:Decode(encoded)
	local roundtripOk = decoded and decoded.d and decoded.d.text == payload and decoded.d.n == 42 and decoded.d.flag == true
	if roundtripOk then
		local chunks = #encoded <= 255 and 1 or math.ceil(#encoded / 254)
		result(true, L.SELFTEST_ROUNDTRIP:format(#encoded, chunks))
	else
		result(false, L.SELFTEST_ROUNDTRIP_FAIL)
	end

	-- 3. Loopback dispatch (receive path without network)
	local reached = false
	ns.Comm:RegisterHandler(self, "SELFTEST_LOOP", function()
		reached = true
	end)
	ns.Comm:SimulateReceive(self.FAKE_MEMBERS[1].name, "SELFTEST_LOOP", { ping = true })
	ns.Comm:UnregisterHandlers(self)
	result(reached, reached and L.SELFTEST_LOOPBACK or L.SELFTEST_LOOPBACK_FAIL)

	-- 4. Which restriction-related APIs this client has (answers TODO(verify in-game) items)
	local apis = {
		"InChatMessagingLockdown=" .. yesNo(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown),
		"C_InstanceEncounter=" .. yesNo(C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress),
		"issecretvalue=" .. yesNo(issecretvalue),
		"GetMirrorTimerProgress=" .. yesNo(GetMirrorTimerProgress),
		"RestrictionEvent=" .. yesNo(not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED")),
		"interface=" .. tostring(select(4, GetBuildInfo())),
	}
	info(L.SELFTEST_APIS:format(table.concat(apis, ", ")))

	-- 5. Real transport: a multi-chunk addon message on the group channel,
	-- which the server echoes back to the sender (needs a group).
	local restricted, reason = ns.Comm:IsRestricted()
	if restricted then
		result(false, L.SELFTEST_TRANSPORT_SKIPPED:format(reason))
		return
	end
	if not ns.Roster:GetChannel() then
		info(L.SELFTEST_TRANSPORT_SOLO)
		return
	end
	local expected = checksum(payload)
	local startedAt = GetTime()
	local done = false
	ns.Comm:RegisterHandler(self, ns.Comm.SELFTEST, function(_, data, sender)
		if done or not ns.Roster:IsPlayer(sender) then
			return
		end
		done = true
		ns.Comm:UnregisterHandlers(self)
		local intact = type(data) == "table" and data.text == payload and data.sum == expected
		result(intact, intact and L.SELFTEST_TRANSPORT_OK:format(GetTime() - startedAt) or L.SELFTEST_TRANSPORT_CORRUPT)
	end)
	local bytes, chunks = ns.Comm:SendSelfTest({ text = payload, sum = expected }, function(allSent)
		if not allSent and not done then
			done = true
			ns.Comm:UnregisterHandlers(self)
			result(false, L.SELFTEST_TRANSPORT_FAILED:format("didSend=false"))
		end
	end)
	info(L.SELFTEST_TRANSPORT_SENT:format(bytes, chunks, self.SELFTEST_TIMEOUT))
	C_Timer.After(self.SELFTEST_TIMEOUT, function()
		if not done then
			done = true
			ns.Comm:UnregisterHandlers(self)
			result(false, L.SELFTEST_TRANSPORT_TIMEOUT:format(self.SELFTEST_TIMEOUT))
		end
	end)
end
