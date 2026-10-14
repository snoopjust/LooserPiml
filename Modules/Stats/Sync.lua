-- Sharing aggregates with LooserPiml friends, and their stats cache.
--
-- Each client sends only its own aggregates (tonight / week / all time),
-- never the raw event log, and only to listed friends who answered the
-- handshake this session (Comm scope "friends", see Core/Friends.lua):
-- when a friend's handshake arrives and after changes (debounced, at most
-- once per BROADCAST_INTERVAL). The "share my stats" setting turns sending
-- off; receiving still works. Restrictions (boss fights) are handled by
-- Comm's hold queue; a newer snapshot replaces an older one that is still
-- waiting there, and recipients are checked again when it is flushed.
--
-- Received aggregates are cached per friend in SavedVariables
-- (db.friendStats) with a timestamp, so the leaderboard can show friends
-- who are offline. The leaderboard lists only friends on the friends list
-- who answered a handshake at least once.
--
-- STATS payload:
--   { mv = Model.VERSION, day = "2026-10-11", week = "2026-10-05",
--     class = "HUNTER", level = 23, gold = copper (only with "Share my gold"),
--     p = { tonight = aggregate, week = aggregate, all = aggregate } }
-- gold is a snapshot of the money on hand, not part of any period. A
-- message without it means the friend doesn't share gold (any more).
-- The day/week keys tell receivers whether "tonight"/"this week" are still
-- the current ones; an outdated tonight counts as empty.
local _, ns = ...

local Stats = ns:GetModule("Stats")

Stats.SYNC_MSG = "STATS"
Stats.BROADCAST_INTERVAL = 30 -- seconds, minimum between two broadcasts

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
		gold = self:GetSharedGold(),
		p = {
			tonight = self.Model.ForSync(aggregates.tonight),
			week = self.Model.ForSync(aggregates.week),
			all = self.Model.ForSync(aggregates.all),
		},
	}
end

function Stats:CanBroadcast()
	return self:IsEnabled() and self.db.share ~= false and ns.Friends:HasRecipients("friends")
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
	local result = ns.Comm:Send(self.SYNC_MSG, self:BuildSyncPayload(), { scope = "friends", prio = "BULK", key = self.SYNC_MSG })
	if result == "queued" then
		self.lastBroadcast = now
	end
	return result
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

-- Stats cache entry of a friend (created on their first STATS message).
function Stats:NoteFriend(name, store)
	store = store or self.db.friendStats
	local friend = store[name]
	if not friend then
		friend = {}
		store[name] = friend
	end
	friend.lastSeen = time()
	friend.class = friend.class or ns.Roster:GetClass(name)
	return friend
end

-- Comm only delivers STATS from listed friends (everything else is dropped
-- before it gets here), or simulated ones in test mode.
function Stats:OnStatsMessage(data, sender, meta)
	if type(data) ~= "table" or type(data.p) ~= "table" then
		return
	end
	local Model = self.Model
	local friend = self:NoteFriend(sender, meta.test and self.fakeFriends or self.db.friendStats)
	friend.class = cleanClass(data.class) or friend.class
	friend.level = type(data.level) == "number" and data.level >= 1 and data.level <= 1000 and math.floor(data.level) or friend.level
	friend.day = type(data.day) == "string" and data.day:sub(1, 10) or nil
	friend.week = type(data.week) == "string" and data.week:sub(1, 10) or nil
	-- Untrusted number: whole copper, 0 .. 10^13 (more than any character can hold).
	local gold = data.gold
	if type(gold) == "number" and gold == gold and gold >= 0 and gold <= 1e13 then
		friend.gold = math.floor(gold)
	else
		friend.gold = nil -- not shared
	end
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

-- Everyone on the leaderboard for a period: me, listed friends who
-- answered a handshake at least once (online or not), and (in test mode)
-- sample friends. { name, class, agg, isSelf, online, lastSeen }
function Stats:GetParticipants(period)
	local list = {
		{
			name = ns.Roster:GetPlayerName(),
			class = ns.Roster:GetPlayerClass(),
			agg = self:GetAggregates()[period],
			isSelf = true,
			online = true,
			gold = self:GetSharedGold(),
		},
	}
	for name, entry in pairs(ns.Friends:GetDB()) do
		if entry.handshake and not ns.Roster:IsPlayer(name) then
			local cached = self.db.friendStats[name]
			list[#list + 1] = {
				name = name,
				class = (cached and cached.class) or entry.class,
				agg = self:GetFriendAggregate(cached, period),
				online = ns.Friends:IsOnline(name),
				lastSeen = (cached and cached.lastSeen) or entry.lastSeen,
				version = entry.version,
				gold = cached and cached.gold,
			}
		end
	end
	if ns.TestMode:IsEnabled() then
		for name, friend in pairs(self.fakeFriends) do
			list[#list + 1] = {
				name = name,
				class = friend.class,
				agg = self:GetFriendAggregate(friend, period),
				online = true,
				lastSeen = friend.lastSeen,
				gold = friend.gold,
				fake = true,
			}
		end
	end
	return list
end

-- Friends online right now who answered the handshake, for the minimap
-- tooltip.
function Stats:CountOnlineFriends()
	return ns.Friends:CountOnlineConfirmed()
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
			-- Kim doesn't share gold, so the gold comparison leaves her out.
			gold = member.name ~= "Kim" and rand(20, 900) * 10000 + rand(0, 9999) or nil,
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
	ns.Events:Register(self, "LP_STATS_CHANGED", function()
		self:RequestBroadcast()
	end)
	-- A friend answered the handshake (after login, when they came online
	-- or were added): they get our current stats (still at most once per
	-- BROADCAST_INTERVAL, to everyone connected).
	ns.Events:Register(self, "LP_FRIEND_CONFIRMED", function()
		self:RequestBroadcast()
	end)
	ns.Events:Register(self, "LP_COMM_SENT", function(_, _, msgType)
		if msgType == self.SYNC_MSG then
			self.lastBroadcast = GetTime()
		end
	end)
end
