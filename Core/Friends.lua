-- LooserPiml friends: the explicit, mutual list of players LooserPiml
-- talks to. This circle of friends, not the WoW party or raid, is what
-- every feature is built around: friends often play separately and only
-- sometimes group up.
--
-- Hard safety rule (CLAUDE.md, STATUS.md): LooserPiml communicates only
-- with players on this list, and only if they listed us too. Nobody else
-- ever receives anything from LooserPiml, not even a hidden addon message.
--   - Transport is always one WHISPER addon message per connected friend.
--     The PARTY/RAID/INSTANCE_CHAT channels are never used: they would
--     reach strangers in a mixed group.
--   - Comm asks Route() who may get a message at the moment it is really
--     sent, so a message held during a boss never reaches someone who was
--     removed meanwhile.
--   - Comm drops every incoming message whose sender isn't listed.
--   - "Mutual" is learned from the handshake (Version.lua): a listed friend
--     who answers our HELLO has listed us too, because their client drops
--     our messages otherwise and never answers. Only those friends get
--     stats and ticker events, and only they appear on the leaderboard.
--   - No discovery: we never send anything to find out who runs LooserPiml.
--   - No GUILD channel, no Battle.net.
--
-- Connected = listed + answered the handshake this session + online.
-- Online: on the character friends list as online (C_FriendList; that's
-- why friends should also be WoW friends), or a connected member of our
-- group (grouping is only one more source of that information, never a
-- precondition). Whispers only go to online friends: whispering someone
-- offline makes the server answer with a "No player named ..." system
-- message. One exception: a handshake reply may go to a friend who just
-- wrote to us (REPLY_WINDOW).
--
-- Storage: LooserPimlDB.friends["Name-Realm"] = { added, handshake, lastSeen, class, version }
--   handshake = time of the last answered handshake (nil: never answered)
local _, ns = ...
local L = ns.L

local Friends = {}
ns:RegisterCore("Friends", Friends)

Friends.MAX_FRIENDS = 40
-- Seconds after login before the first handshake: lets the friends list
-- and the group roster arrive from the server.
Friends.LOGIN_DELAY = 5
-- A reply may go to a friend who messaged us within this many seconds,
-- even if neither the friends list nor the group shows them online: they
-- obviously are, and without the answer the handshake could never finish
-- when only they have us on their character friends list.
Friends.REPLY_WINDOW = 30

-- Session state (never saved)
Friends.confirmed = {} -- fullName -> true: answered our handshake in this session
Friends.online = {}    -- fullName -> true: online at the last check
Friends.heard = {}     -- fullName -> GetTime() of their last message
Friends.ready = false  -- set LOGIN_DELAY seconds after login

-- Message scopes (who a message may go to, see Allowed):
--   "handshake"  listed friends (HELLO only: this is how mutual is learned)
--   "friends"    listed friends who answered the handshake this session
--                (everything else: ticker events, stats, self-test)
Friends.SCOPES = { handshake = true, friends = true }

function Friends:GetDB()
	return ns.DB:Get("friends")
end

----------------------------------------------------------------------
-- Names
----------------------------------------------------------------------

-- What the user typed -> "Name-Realm", or nil if it can't be a character
-- name. "max" and "Max" become "Max-OurRealm"; "max-Some Realm" becomes
-- "Max-SomeRealm" (realms lose spaces and hyphens in "Name-Realm", like
-- GetNormalizedRealmName). Letters only in the name part, no spaces (UTF-8
-- letters are kept as typed, string.upper only knows ASCII).
function Friends:ParseName(input)
	if type(input) ~= "string" or ns.IsSecret(input) then
		return nil
	end
	input = input:gsub("^%s+", ""):gsub("%s+$", "")
	-- "Headdleonty Kneadmetal": first name and surname (Forever megaserver,
	-- see Roster:Normalize) -> "Headdleonty-Kneadmetal".
	local first, surname = input:match("^([%a\128-\255]+)%s+([%a\128-\255]+)$")
	if first and #first >= 2 and #first <= 48 and #surname >= 2 and #surname <= 48 then
		local function capital(word)
			return word:sub(1, 1):upper() .. word:sub(2):lower()
		end
		return capital(first) .. "-" .. capital(surname)
	end
	local name, realm = input:match("^([^%-]+)%-(.*)$")
	name = (name or input):gsub("%s+$", "") -- "Max - Realm"; spaces inside a name are refused below
	if not name:find("^[%a\128-\255]+$") or #name < 2 or #name > 48 then
		return nil
	end
	name = name:sub(1, 1):upper() .. name:sub(2):lower()
	if realm then
		realm = realm:gsub("[%s%-]", "")
		if realm == "" then
			realm = nil
		elseif not realm:find("^[%w\128-\255']+$") or #realm > 64 then
			return nil
		end
	end
	if realm then
		return name .. "-" .. realm
	end
	return ns.Roster:Normalize(name)
end

-- A name from game text (duel messages, DUEL_REQUESTED) -> the friend key.
-- Usually just Normalize; a bare first name that matches exactly one listed
-- friend's first name resolves to that friend (on the Forever megaserver
-- such texts may leave out the surname, TODO(verify in-game)).
function Friends:Resolve(name)
	local full = ns.Roster:Normalize(name)
	if not full or self:IsListed(full) or name:find("[%s%-]") then
		return full
	end
	local match
	for listed in pairs(self:GetDB()) do
		if ns.Roster:Short(listed) == name then
			if match then
				return full -- ambiguous: two friends with that first name
			end
			match = listed
		end
	end
	return match or full
end

-- The name SendAddonMessage and C_FriendList expect: "Name" for our own
-- realm, "Name-Realm" for others ("First-Surname" on the Forever
-- megaserver, which the server delivers).
function Friends:GetShortTarget(full)
	if Ambiguate then
		return Ambiguate(full, "none")
	end
	return full
end

----------------------------------------------------------------------
-- The list
----------------------------------------------------------------------

function Friends:IsListed(name)
	local full = ns.Roster:Normalize(name)
	local db = self:GetDB()
	return full ~= nil and db ~= nil and db[full] ~= nil
end

function Friends:Count()
	local count = 0
	for _ in pairs(self:GetDB()) do
		count = count + 1
	end
	return count
end

-- Returns the full name, or nil plus a message for the user.
function Friends:Add(input)
	local full = self:ParseName(input)
	if not full then
		return nil, L.FRIENDS_ERR_NAME
	end
	if ns.Roster:IsPlayer(full) then
		return nil, L.FRIENDS_ERR_SELF
	end
	local db = self:GetDB()
	if db[full] then
		return nil, L.FRIENDS_ERR_LISTED:format(ns.Roster:Short(full))
	end
	if self:Count() >= self.MAX_FRIENDS then
		return nil, L.FRIENDS_ERR_FULL:format(self.MAX_FRIENDS)
	end
	db[full] = { added = time(), class = ns.Roster:GetClass(full) }
	ns.Log:Debug("Friends: added %s", full)
	ns.Events:Fire("LP_FRIENDS_CHANGED", full)
	-- Say hello right away if they are online; they answer once they
	-- added us too.
	self:UpdateOnline()
	return full
end

-- Removing stops all traffic to them at once: Route() reads the list for
-- every message, including messages that are still held.
function Friends:Remove(name)
	local full = ns.Roster:Normalize(name)
	local db = self:GetDB()
	if not full or not db[full] then
		return false
	end
	db[full] = nil
	self.confirmed[full] = nil
	self.online[full] = nil
	self.heard[full] = nil
	ns.Version.known[full] = nil
	ns.Log:Debug("Friends: removed %s", full)
	ns.Events:Fire("LP_FRIENDS_CHANGED", full)
	return true
end

-- Sorted list for the UI: { name, short, class, added, handshake, lastSeen, version, confirmed, online }
function Friends:GetList()
	local list = {}
	for full, entry in pairs(self:GetDB()) do
		list[#list + 1] = {
			name = full,
			short = ns.Roster:Short(full),
			class = ns.Roster:GetClass(full) or entry.class,
			added = entry.added,
			handshake = entry.handshake,
			lastSeen = entry.lastSeen,
			version = entry.version,
			confirmed = self.confirmed[full] == true,
			online = self:IsOnline(full),
		}
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Real group members who are not listed yet ("Add from group"). Never the
-- fake test-mode members: "Max-YourRealm" may well be a real stranger.
function Friends:GetGroupCandidates()
	local list = {}
	for _, member in ipairs(ns.Roster:GetRealOthers()) do
		if not self:IsListed(member.name) then
			list[#list + 1] = member
		end
	end
	return list
end

-- Character names on the WoW friends list who aren't listed yet ("Add from
-- WoW friends list"), online ones first: { name, short, class, connected }.
-- FriendInfo only has the localized class name; the class file name (for
-- the color) is looked up in Blizzard's localized class tables.
-- TODO(verify in-game): LOCALIZED_CLASS_NAMES_MALE/FEMALE exist on Forever.
local function classFromLocalized(className)
	if type(className) ~= "string" or ns.IsSecret(className) then
		return nil
	end
	for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
		for classFile, localized in pairs(names) do
			if localized == className then
				return classFile
			end
		end
	end
	return nil
end

function Friends:GetWoWFriendCandidates()
	local list = {}
	local api = C_FriendList
	local count = api and api.GetNumFriends and api.GetNumFriends()
	if ns.IsSecret(count) or type(count) ~= "number" or not api.GetFriendInfoByIndex then
		return list
	end
	for i = 1, count do
		local info = api.GetFriendInfoByIndex(i)
		if type(info) == "table" and not ns.IsSecret(info) and type(info.name) == "string" and not ns.IsSecret(info.name) then
			local full = ns.Roster:Normalize(info.name)
			if full and not ns.Roster:IsPlayer(full) and not self:IsListed(full) then
				list[#list + 1] = {
					name = full,
					short = ns.Roster:Short(full),
					class = classFromLocalized(info.className),
					connected = not ns.IsSecret(info.connected) and info.connected == true,
				}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.connected ~= b.connected then
			return a.connected
		end
		return a.name < b.name
	end)
	return list
end

----------------------------------------------------------------------
-- Handshake state
----------------------------------------------------------------------

-- Answered the handshake in this session: they listed us too.
function Friends:IsConfirmed(name)
	local full = ns.Roster:Normalize(name)
	return full ~= nil and self.confirmed[full] == true and self:IsListed(full)
end

-- Answered a handshake at some point (saved), for the leaderboard, which
-- also shows friends who are offline right now.
function Friends:HasHandshake(name)
	local full = ns.Roster:Normalize(name)
	local entry = full and self:GetDB()[full]
	return entry ~= nil and entry.handshake ~= nil
end

-- Called by Version for every HELLO from a listed friend (Comm already
-- dropped everyone else).
function Friends:OnHandshake(full, version)
	local entry = self:GetDB()[full]
	if not entry then
		return
	end
	entry.handshake = time()
	entry.lastSeen = entry.handshake
	entry.version = version
	entry.class = ns.Roster:GetClass(full) or entry.class
	local wasConfirmed = self.confirmed[full]
	self.confirmed[full] = true
	ns.Events:Fire("LP_FRIENDS_CHANGED", full)
	if not wasConfirmed then
		ns.Events:Fire("LP_FRIEND_CONFIRMED", full)
	end
end

----------------------------------------------------------------------
-- Online state
----------------------------------------------------------------------

-- Online on the character friends list, or a connected member of our
-- group. Battle.net friends are deliberately not used.
function Friends:IsOnline(full)
	local getInfo = C_FriendList and C_FriendList.GetFriendInfo
	if getInfo then
		local info = getInfo(self:GetShortTarget(full))
		if type(info) == "table" and not ns.IsSecret(info) and not ns.IsSecret(info.connected) and info.connected then
			return true
		end
	end
	local member = ns.Roster.members[full]
	return member ~= nil and member.connected ~= false
end

-- Listed, answered the handshake this session, and online: gets messages.
function Friends:IsConnected(name)
	local full = ns.Roster:Normalize(name)
	return full ~= nil and self:IsConfirmed(full) and self:IsOnline(full)
end

-- Connected friends, sorted.
function Friends:GetConnected()
	local list = {}
	for full in pairs(self:GetDB()) do
		if self.confirmed[full] and self:IsOnline(full) then
			list[#list + 1] = full
		end
	end
	table.sort(list)
	return list
end

-- Greets friends who just came online (or were added) and forgets the
-- handshake of friends who went offline: when they come back, they may
-- have removed us meanwhile, so they get a fresh handshake first.
function Friends:UpdateOnline()
	if not self.ready then
		return
	end
	local greet = {}
	for full in pairs(self:GetDB()) do
		local online = self:IsOnline(full)
		if online and not self.online[full] then
			if not self.confirmed[full] then
				greet[#greet + 1] = full
			end
		elseif not online and self.online[full] then
			self.confirmed[full] = nil
		end
		self.online[full] = online or nil
	end
	if #greet > 0 then
		table.sort(greet)
		ns.Version:Greet(greet)
	end
end

function Friends:NoteHeard(full)
	self.heard[full] = GetTime()
end

local function heardRecently(self, full)
	local at = self.heard[full]
	return at ~= nil and GetTime() - at <= self.REPLY_WINDOW
end

function Friends:CountOnlineConfirmed()
	return #self:GetConnected()
end

----------------------------------------------------------------------
-- Routing (used by Comm for every outgoing message)
----------------------------------------------------------------------

-- May `full` receive a message of this scope? (Online is checked
-- separately in Route.)
function Friends:Allowed(full, scope)
	if ns.Roster:IsPlayer(full) or not self:IsListed(full) then
		return false
	end
	if scope == "handshake" then
		return true
	end
	return scope == "friends" and self.confirmed[full] == true
end

local function toSet(names)
	if not names then
		return nil
	end
	local set = {}
	for _, name in ipairs(names) do
		local full = ns.Roster:Normalize(name)
		if full then
			set[full] = true
		end
	end
	return set
end

-- The friends who get a message: a sorted array, one WHISPER each. `to`
-- (optional) restricts the message to these names; isReply allows
-- whispering a `to` friend who just wrote to us (REPLY_WINDOW).
-- Never a group channel, whatever the group looks like.
function Friends:Route(scope, to, isReply)
	assert(self.SCOPES[scope], "unknown scope " .. tostring(scope))
	local only = toSet(to)
	local recipients = {}
	for full in pairs(self:GetDB()) do
		local reachable = self:IsOnline(full) or (isReply and only and heardRecently(self, full))
		if self:Allowed(full, scope) and (not only or only[full]) and reachable then
			recipients[#recipients + 1] = full
		end
	end
	table.sort(recipients)
	return recipients
end

function Friends:HasRecipients(scope)
	return #self:Route(scope) > 0
end

----------------------------------------------------------------------
-- /lp friends
----------------------------------------------------------------------

function Friends:PrintList()
	local list = self:GetList()
	if #list == 0 then
		ns.Log:Print(L.FRIENDS_NONE)
		return
	end
	for _, friend in ipairs(list) do
		ns.Log:Print("  %s - %s", ns.Roster:ColorName(friend.name, friend.class), self:StatusText(friend))
	end
end

-- "connected" / "waiting for them to add you" / "offline"
function Friends:StatusText(friend)
	if friend.confirmed and friend.online then
		return L.FRIENDS_STATUS_CONNECTED
	elseif friend.online then
		return L.FRIENDS_STATUS_WAITING
	end
	return L.FRIENDS_STATUS_OFFLINE
end

function Friends:OnSlash(args)
	local action, rest = (args or ""):match("^%s*(%S*)%s*(.-)%s*$")
	action = (action or ""):lower()
	if action == "add" and rest ~= "" then
		local full, err = self:Add(rest)
		ns.Log:Print(full and L.FRIENDS_ADDED:format(full) or err)
	elseif action == "remove" and rest ~= "" then
		local full = self:ParseName(rest)
		if full and self:Remove(full) then
			ns.Log:Print(L.FRIENDS_REMOVED:format(full))
		else
			ns.Log:Print(L.FRIENDS_ERR_NOT_LISTED:format(rest))
		end
	elseif action == "list" then
		self:PrintList()
	else
		ns.Window:Open("friends")
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Friends:OnInitialize()
	ns.Slash:Register("friends", function(args)
		self:OnSlash(args)
	end, "[add|remove <name> | list]", L.HELP_FRIENDS)
end

-- Friends never need slash commands, so tell them once after login why
-- nothing is shared while their list is empty (local chat line only).
function Friends:MaybeHint()
	if self.hinted or self:Count() > 0 then
		return
	end
	self.hinted = true
	ns.Log:Print(L.FRIENDS_HINT_EMPTY)
end

-- An earlier build could list the own character (offered under "Add from
-- group"); such an entry would only ever whisper ourselves.
function Friends:RemoveSelf()
	for full in pairs(self:GetDB()) do
		if ns.Roster:IsPlayer(full) then
			self:GetDB()[full] = nil
		end
	end
end

function Friends:OnEnable()
	self:RemoveSelf()
	-- Group members' connection state is one more source of "online".
	ns.Events:Register(self, "LP_ROSTER_UPDATED", "UpdateOnline")
	-- Fires when the character friends list changes, including friends
	-- logging in or out.
	ns.Events:Register(self, "FRIENDLIST_UPDATE", "UpdateOnline")
	C_Timer.After(self.LOGIN_DELAY, function()
		self.ready = true
		self:UpdateOnline()
		self:MaybeHint()
	end)
end
