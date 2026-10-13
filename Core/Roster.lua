-- Group members, full names and class colors.
--
-- The WoW group is only context for LooserPiml (who is online, "Add from
-- group", time spent grouped with a friend); nothing is ever sent to the
-- group (see Core/Friends.lua).
--
-- Names are stored as "Name-Realm" everywhere (stats keys, version table,
-- friends list).
-- Fires LP_ROSTER_CHANGED(joined, left) with arrays of full names, and
-- LP_ROSTER_UPDATED after every scan (also for connection changes).
local _, ns = ...

local Roster = {}
ns:RegisterCore("Roster", Roster)

Roster.members = {} -- fullName -> { name, short, class, unit, connected }
Roster.fake = {}    -- fullName -> fake friend, test mode only

-- GetNormalizedRealmName has spaces and hyphens stripped, the same form the
-- server uses in "Name-Realm" sender names. It can be nil very early during
-- login, hence the fallback.
local function realmName()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if not realm or realm == "" then
		realm = (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "")
	end
	return realm
end

-- "Max" -> "Max-Realm"; "Max-Other" stays as is.
function Roster:Normalize(name)
	if type(name) ~= "string" or name == "" or ns.IsSecret(name) then
		return nil
	end
	if name:find("-", 1, true) then
		return name
	end
	local realm = realmName()
	if realm == "" then
		return name
	end
	return name .. "-" .. realm
end

function Roster:Short(name)
	return (tostring(name):gsub("%-.*$", ""))
end

function Roster:GetPlayerName()
	if not self.playerName then
		local name = UnitName("player")
		if ns.IsSecret(name) then
			return nil
		end
		self.playerName = self:Normalize(name)
	end
	return self.playerName
end

function Roster:IsPlayer(name)
	return name ~= nil and self:Normalize(name) == self:GetPlayerName()
end

function Roster:GetPlayerClass()
	local _, class = UnitClass("player")
	if ns.IsSecret(class) then
		return nil
	end
	return class
end

-- UnitName returns a realm only for players from other realms. Midnight can
-- make unit identity secret in combat (documented for non-player units;
-- group members are players, but we stay defensive). "Unknown"
-- (UNKNOWNOBJECT) shows up while unit data is still loading; the next
-- GROUP_ROSTER_UPDATE fills it in.
local function readUnit(unit)
	local exists = UnitExists(unit)
	if ns.IsSecret(exists) or not exists then
		return nil
	end
	local name, realm = UnitName(unit)
	if not name or ns.IsSecret(name) or ns.IsSecret(realm) or name == UNKNOWNOBJECT then
		return nil
	end
	-- Realm names in "Name-Realm" have no spaces or hyphens. UnitName may
	-- return a realm differently formatted than GetNormalizedRealmName, which
	-- made the own character look like a stranger ("Add from group" offered
	-- it). The player itself is always keyed like GetPlayerName().
	local full
	if unit == "player" then
		full = Roster:GetPlayerName()
	elseif realm and realm ~= "" then
		full = name .. "-" .. realm:gsub("[%s%-]", "")
	else
		full = Roster:Normalize(name)
	end
	if not full then
		return nil
	end
	local _, class = UnitClass(unit)
	if ns.IsSecret(class) then
		class = nil
	end
	-- Offline members stay in the group. Whispering them would make the
	-- server answer with a "No player named ..." system message, so
	-- Friends only counts connected members as online. Unknown (secret)
	-- counts as connected.
	local connected = UnitIsConnected and UnitIsConnected(unit)
	if ns.IsSecret(connected) then
		connected = nil
	end
	return { name = full, short = name, class = class, unit = unit, connected = connected ~= false }
end

function Roster:Scan()
	local found = {}
	local function add(unit)
		local member = readUnit(unit)
		if member then
			found[member.name] = member
		end
	end
	-- raid1..N include the player, party1..4 don't. GetNumGroupMembers counts
	-- the player, GetNumSubgroupMembers doesn't.
	add("player")
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			add("raid" .. i)
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			add("party" .. i)
		end
	end

	local joined, left = {}, {}
	for name in pairs(found) do
		if not self.members[name] then
			joined[#joined + 1] = name
		end
	end
	for name in pairs(self.members) do
		if not found[name] then
			left[#left + 1] = name
		end
	end
	table.sort(joined)
	table.sort(left)
	self.members = found
	if #joined > 0 or #left > 0 then
		ns.Events:Fire("LP_ROSTER_CHANGED", joined, left)
	end
	ns.Events:Fire("LP_ROSTER_UPDATED")
end

function Roster:GetMember(name)
	local full = self:Normalize(name)
	return full and (self.members[full] or self.fake[full])
end

function Roster:GetClass(name)
	local member = self:GetMember(name)
	return member and member.class
end

-- Real group members other than the player (never the fake ones), sorted.
function Roster:GetRealOthers()
	local list = {}
	for name, member in pairs(self.members) do
		if not self:IsPlayer(name) then
			list[#list + 1] = member
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Other group members plus, in test mode, the fake friends, sorted by name.
function Roster:GetOthers()
	local me = self:GetPlayerName()
	local list = {}
	for name, member in pairs(self.members) do
		if name ~= me then
			list[#list + 1] = member
		end
	end
	for _, member in pairs(self.fake) do
		list[#list + 1] = member
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

function Roster:ColorName(name, class)
	local short = self:Short(name)
	class = class or self:GetClass(name)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then
		return "|c" .. color.colorStr .. short .. "|r"
	end
	return short
end

function Roster:IsInGroup()
	return IsInGroup() == true
end

-- Test mode ------------------------------------------------------------

function Roster:SetFakeMembers(list)
	local previous = self.fake
	self.fake = {}
	local joined, left = {}, {}
	for _, entry in ipairs(list or {}) do
		local full = self:Normalize(entry.name)
		self.fake[full] = { name = full, short = entry.name, class = entry.class, fake = true }
		if not previous[full] then
			joined[#joined + 1] = full
		end
	end
	for full in pairs(previous) do
		if not self.fake[full] then
			left[#left + 1] = full
		end
	end
	table.sort(joined)
	table.sort(left)
	if #joined > 0 or #left > 0 then
		ns.Events:Fire("LP_ROSTER_CHANGED", joined, left, true)
	end
end

function Roster:OnEnable()
	ns.Events:Register(self, "GROUP_ROSTER_UPDATE", "Scan")
	ns.Events:Register(self, "PLAYER_ENTERING_WORLD", "Scan")
	-- Fires when a group member goes offline or comes back (unit token).
	ns.Events:Register(self, "UNIT_CONNECTION", "Scan")
	self:Scan()
end
