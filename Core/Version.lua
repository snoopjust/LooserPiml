-- Version handshake.
--
-- On login and whenever someone joins the group we broadcast HELLO with our
-- version. Everyone who receives a (non-reply) HELLO answers once with their
-- own. Mismatches are reported locally, once per player and session.
local ADDON_NAME, ns = ...
local L = ns.L

local Version = {}
ns:RegisterCore("Version", Version)

Version.MSG = "HELLO"
Version.HELLO_COOLDOWN = 10 -- seconds between our broadcasts (coalesced)
Version.LOGIN_DELAY = 5     -- let the client settle after login before sending
Version.TEST_BASELINE = "1.0.0" -- dev builds compare as this in test mode

Version.known = {}  -- fullName -> { version, protocol }
Version.warned = {} -- fullName -> true

-- The packager replaces @project-version@ in the .toc with the git tag. In a
-- git checkout (junction) the placeholder stays. GetAddOnMetadata moved
-- into C_AddOns in 10.1; the global is the old name, kept as a fallback.
local function readVersion()
	local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMetadata and getMetadata(ADDON_NAME, "Version")
	if type(version) ~= "string" or version == "" or version:find("@", 1, true) then
		return "dev" -- unpackaged checkout (@project-version@ not replaced)
	end
	return version
end

-- "v1.2.3", "1.2", "1.2.3-beta1", "v1.2.3-4-gabcdef" -> { 1, 2, 3 }; nil if not a version.
function Version.Parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local major, minor, patch = text:match("^v?(%d+)%.(%d+)%.?(%d*)")
	if not major then
		return nil
	end
	return { tonumber(major), tonumber(minor), tonumber(patch) or 0 }
end

-- -1 if a < b, 0 if equal, 1 if a > b, nil if either can't be compared (dev builds).
function Version.Compare(a, b)
	local pa, pb = Version.Parse(a), Version.Parse(b)
	if not pa or not pb then
		return nil
	end
	for i = 1, 3 do
		if pa[i] ~= pb[i] then
			return pa[i] < pb[i] and -1 or 1
		end
	end
	return 0
end

function Version:GetCurrent()
	if not self.current then
		self.current = readVersion()
	end
	return self.current
end

-- What we compare others against. Dev builds have no number; in test mode
-- they pretend to be TEST_BASELINE so the warnings can be tried solo.
function Version:GetComparable()
	local current = self:GetCurrent()
	if Version.Parse(current) then
		return current
	end
	if ns.TestMode:IsEnabled() then
		return self.TEST_BASELINE
	end
	return nil
end

function Version:SendHello(isReply)
	local now = GetTime()
	if self.lastHello and now - self.lastHello < self.HELLO_COOLDOWN then
		-- Coalesce bursts (several joins, several HELLOs) into one later send.
		if not self.helloScheduled then
			self.helloScheduled = true
			C_Timer.After(self.HELLO_COOLDOWN - (now - self.lastHello), function()
				self.helloScheduled = false
				self:SendHello(isReply)
			end)
		end
		return "scheduled"
	end
	self.lastHello = now
	return ns.Comm:Send(self.MSG, {
		ver = self:GetCurrent(),
		proto = ns.Comm.PROTOCOL,
		reply = isReply or nil,
	})
end

function Version:Check(sender, version, protocol)
	if self.warned[sender] then
		return
	end
	local name = ns.Roster:ColorName(sender)
	if protocol ~= ns.Comm.PROTOCOL then
		self.warned[sender] = true
		ns.Log:Print(L.VERSION_INCOMPATIBLE, name, tostring(version))
		return
	end
	local cmp = Version.Compare(version, self:GetComparable())
	if cmp == -1 then
		self.warned[sender] = true
		ns.Log:Print(L.VERSION_OLDER, name, version, self:GetComparable())
	elseif cmp == 1 then
		self.warned[sender] = true
		ns.Log:Print(L.VERSION_NEWER, name, version)
	end
end

function Version:OnHello(data, sender, meta)
	if type(data) ~= "table" then
		return
	end
	-- Shown in chat: keep only version characters (no "|" escape sequences).
	local version = type(data.ver) == "string" and data.ver:gsub("[^%w%.%-%+]", ""):sub(1, 40) or ""
	if version == "" then
		version = "?"
	end
	local protocol = type(data.proto) == "number" and data.proto or meta.protocol
	self.known[sender] = { version = version, protocol = protocol }
	self:Check(sender, version, protocol)
	if not data.reply and not meta.test then
		self:SendHello(true)
	end
end

function Version:OnRosterChanged(_, joined, _, isFake)
	if isFake or #joined == 0 then
		return
	end
	for _, name in ipairs(joined) do
		if not ns.Roster:IsPlayer(name) then
			self:SendHello(false)
			return
		end
	end
end

function Version:PrintVersions()
	ns.Log:Print(L.VERSION_SELF, self:GetCurrent(), ns.Comm.PROTOCOL)
	local others = ns.Roster:GetOthers()
	if #others == 0 then
		ns.Log:Print(L.VERSION_NONE)
		return
	end
	for _, member in ipairs(others) do
		local info = self.known[member.name]
		ns.Log:Print(L.VERSION_MEMBER, ns.Roster:ColorName(member.name, member.class), info and info.version or L.VERSION_UNKNOWN)
	end
end

function Version:OnEnable()
	ns.Comm:RegisterHandler(self, self.MSG, self.OnHello)
	ns.Events:Register(self, "LP_ROSTER_CHANGED", "OnRosterChanged")
	C_Timer.After(self.LOGIN_DELAY, function()
		if ns.Roster:GetChannel() then
			self:SendHello(false)
		end
	end)
end
