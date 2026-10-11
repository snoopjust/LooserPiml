-- Sharing aggregates with friends, and the friends cache.
--
-- Each client broadcasts only its own aggregates (tonight / week / all
-- time), never the raw event log: on login, when someone joins the group,
-- and after changes (debounced, at most once per BROADCAST_INTERVAL). The
-- "share my stats" setting turns broadcasting off; receiving still works.
-- Restrictions (boss fights) are handled by Comm's hold queue; a newer
-- snapshot replaces an older one that is still waiting there.
--
-- A "friend" is any LooserPiml user we have been grouped with (seen via
-- HELLO or STATS). Their latest aggregates are kept in SavedVariables with
-- a timestamp, so the leaderboard can show friends who are offline.
--
-- STATS payload:
--   { mv = Model.VERSION, day = "2026-10-11", week = "2026-10-05",
--     class = "HUNTER", level = 23,
--     p = { tonight = aggregate, week = aggregate, all = aggregate } }
-- The day/week keys tell receivers whether "tonight"/"this week" are still
-- the current ones; an outdated tonight counts as empty.
local _, ns = ...

local Stats = ns:GetModule("Stats")

Stats.SYNC_MSG = "STATS"
Stats.BROADCAST_INTERVAL = 30 -- seconds, minimum between two broadcasts
Stats.LOGIN_BROADCAST_DELAY = 8 -- after HELLO (5 s) has gone out

Stats.fakeFriends = {} -- test mode only, never saved

local function cleanClass(class)
	if type(class) == "string" and class:match("^[A-Z]+$") and #class <= 20 then
		return class
	end
	return nil
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

function Stats:BuildSyncPayload()
	local now = GetServerTime()
	local aggregates = self:GetAggregates()
	return {
		mv = self.Model.VERSION,
		day = self.Model.DayKey(now),
		week = self.Model.WeekKey(now),
		class = ns.Roster:GetPlayerClass(),
		level = ns.PlayerEvents:GetLevel(),
		p = {
			tonight = self.Model.ForSync(aggregates.tonight),
			week = self.Model.ForSync(aggregates.week),
			all = self.Model.ForSync(aggregates.all),
		},
	}
end

function Stats:CanBroadcast()
	return self:IsEnabled() and self.db.share ~= false and ns.Roster:GetChannel() ~= nil
end

-- Sends now, unless the last broadcast was less than BROADCAST_INTERVAL
-- ago; then it is scheduled for the end of the interval (one send for any
-- number of changes in between).
function Stats:RequestBroadcast()
	if not self:CanBroadcast() then
		return "off"
	end
	local now = GetTime()
	local wait = self.lastBroadcast and (self.lastBroadcast + self.BROADCAST_INTERVAL - now) or 0
	-- Tolerance: timers fire with float rounding; a leftover wait of a few
	-- microseconds must not schedule yet another timer.
	if wait > 0.05 then
		if not self.broadcastScheduled then
			self.broadcastScheduled = true
			C_Timer.After(wait, function()
				self.broadcastScheduled = false
				self:RequestBroadcast()
			end)
		end
		return "scheduled"
	end
	-- lastBroadcast is set by LP_COMM_SENT when the message really goes out
	-- (now, or later when a held one is flushed after a boss fight). While
	-- held, queuing counts too, so a fight full of changes doesn't rebuild
	-- the snapshot on every single one.
	local result = ns.Comm:Send(self.SYNC_MSG, self:BuildSyncPayload(), "BULK", self.SYNC_MSG)
	if result == "queued" then
		self.lastBroadcast = now
	end
	return result
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

-- Friend entry (created on first contact).
function Stats:NoteFriend(name, store)
	store = store or self.db.friends
	local friend = store[name]
	if not friend then
		friend = {}
		store[name] = friend
	end
	friend.lastSeen = time()
	friend.class = friend.class or ns.Roster:GetClass(name)
	local known = ns.Version.known[name]
	if known then
		friend.version = known.version
	end
	return friend
end

function Stats:OnHello(_, sender, meta)
	if meta.test then
		return
	end
	self:NoteFriend(sender)
	ns.Events:Fire("LP_FRIENDS_CHANGED", sender)
end

function Stats:OnStatsMessage(data, sender, meta)
	if type(data) ~= "table" or type(data.p) ~= "table" then
		return
	end
	local Model = self.Model
	local friend = self:NoteFriend(sender, meta.test and self.fakeFriends or self.db.friends)
	friend.class = cleanClass(data.class) or friend.class
	friend.level = type(data.level) == "number" and data.level >= 1 and data.level <= 1000 and math.floor(data.level) or friend.level
	friend.day = type(data.day) == "string" and data.day:sub(1, 10) or nil
	friend.week = type(data.week) == "string" and data.week:sub(1, 10) or nil
	friend.updated = time()
	friend.stats = {
		tonight = Model.Sanitize(data.p.tonight),
		week = Model.Sanitize(data.p.week),
		all = Model.Sanitize(data.p.all),
	}
	ns.Events:Fire("LP_FRIENDS_CHANGED", sender)
end

-- A friend's aggregate for a period; "tonight"/"week" from a past day or
-- week count as empty (they were sent before the period started).
function Stats:GetFriendAggregate(friend, period)
	local stats = friend and friend.stats
	if not stats or not stats[period] then
		return self.Model.Empty()
	end
	local now = GetServerTime()
	if period == "tonight" and friend.day ~= self.Model.DayKey(now) then
		return self.Model.Empty()
	elseif period == "week" and friend.week ~= self.Model.WeekKey(now) then
		return self.Model.Empty()
	end
	return stats[period]
end

-- In the group right now, or online per the character friends list.
function Stats:IsFriendOnline(name)
	if ns.Roster.members[name] then
		return true
	end
	local getInfo = C_FriendList and C_FriendList.GetFriendInfo
	if getInfo then
		local info = getInfo(ns.Roster:Short(name))
		if type(info) == "table" and not ns.IsSecret(info.connected) and info.connected then
			return true
		end
	end
	return false
end

-- Everyone on the leaderboard for a period: me, cached friends, and (in
-- test mode) sample friends. { name, class, agg, isSelf, online, lastSeen }
function Stats:GetParticipants(period)
	local list = {
		{
			name = ns.Roster:GetPlayerName(),
			class = ns.Roster:GetPlayerClass(),
			agg = self:GetAggregates()[period],
			isSelf = true,
			online = true,
		},
	}
	local function addFrom(store, fake)
		for name, friend in pairs(store) do
			if not ns.Roster:IsPlayer(name) then
				list[#list + 1] = {
					name = name,
					class = friend.class,
					agg = self:GetFriendAggregate(friend, period),
					online = fake or self:IsFriendOnline(name),
					lastSeen = friend.lastSeen,
					version = friend.version,
					fake = fake,
				}
			end
		end
	end
	addFrom(self.db.friends, false)
	if ns.TestMode:IsEnabled() then
		addFrom(self.fakeFriends, true)
	end
	return list
end

-- Friends (with LooserPiml) online right now, for the minimap tooltip.
function Stats:CountOnlineFriends()
	local count = 0
	for name in pairs(self.db.friends) do
		if not ns.Roster:IsPlayer(name) and self:IsFriendOnline(name) then
			count = count + 1
		end
	end
	return count
end

----------------------------------------------------------------------
-- Test mode: sample friends for viewing the leaderboard solo
----------------------------------------------------------------------

-- Deterministic pseudo-random numbers, so the sample looks the same each time.
local function sampleRandom(seed)
	local x = seed
	return function(low, high)
		x = (x * 1103515245 + 12345) % 2147483648
		return low + (math.floor(x / 65536) % (high - low + 1))
	end
end

function Stats:FillSampleFriends()
	if not ns.TestMode:IsEnabled() then
		return false
	end
	local Model = self.Model
	local now = GetServerTime()
	self.fakeFriends = {}
	for i, member in ipairs(ns.TestMode.FAKE_MEMBERS) do
		local rand = sampleRandom(i * 7919)
		local stats = {}
		for _, period in ipairs(Model.PERIODS) do
			local scale = period == "tonight" and 1 or (period == "week" and 4 or 15)
			local agg = Model.Empty()
			local t = now - rand(60, 3000)
			Model.Add(agg, "deaths", rand(0, 4) * scale, t)
			Model.Add(agg, "drowned", rand(0, 1) * scale, t + rand(1, 100))
			Model.Add(agg, "moneyLooted", rand(5, 400) * 100 * scale, t)
			Model.Add(agg, "quests", rand(0, 8) * scale, t)
			Model.Add(agg, "levelUps", rand(0, 2) * scale, t)
			local levels = rand(1, 3) * scale
			Model.Add(agg, "levelTimeCount", levels, t)
			Model.Add(agg, "levelTime", levels * rand(1200, 4800), t)
			agg.moneyIn.loot = agg.n.moneyLooted
			stats[period] = agg
		end
		local name = ns.Roster:Normalize(member.name)
		self.fakeFriends[name] = {
			class = member.class,
			lastSeen = now,
			day = Model.DayKey(now),
			week = Model.WeekKey(now),
			stats = stats,
		}
	end
	ns.Events:Fire("LP_FRIENDS_CHANGED")
	return true
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Stats:EnableSync()
	ns.Comm:RegisterHandler(self, self.SYNC_MSG, self.OnStatsMessage)
	ns.Comm:RegisterHandler(self, ns.Version.MSG, self.OnHello)
	ns.Events:Register(self, "LP_STATS_CHANGED", function()
		self:RequestBroadcast()
	end)
	ns.Events:Register(self, "LP_COMM_SENT", function(_, _, msgType)
		if msgType == self.SYNC_MSG then
			self.lastBroadcast = GetTime()
		end
	end)
	ns.Events:Register(self, "LP_ROSTER_CHANGED", function(_, _, joined, _, isFake)
		if isFake then
			return
		end
		for _, name in ipairs(joined or {}) do
			if not ns.Roster:IsPlayer(name) then
				self:RequestBroadcast()
				return
			end
		end
	end)
	C_Timer.After(self.LOGIN_BROADCAST_DELAY, function()
		self:RequestBroadcast()
	end)
end
