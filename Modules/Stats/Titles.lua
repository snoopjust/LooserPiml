-- The LooserPiml title: last place of the all-time duel ladder
-- (Leaderboard.LooserPiml, at least LOOSERPIML_MIN_DUELS confirmed ranked
-- duels). Who holds it, the badge after their name (Window badge
-- providers: PvP tab, Leaderboard rows, Friends tab), and the banner when
-- it changes hands.
--
-- No message of its own: every client works it out from the duel data it
-- already has (STATS), so the banner appears on each screen once both
-- duelists' records have arrived there (up to ~30 s after the duel).
--
-- Change detection (saved in Stats.db.looserPiml = { name, confirmed }):
-- the banner comes only when the holder changed AND more duels are
-- confirmed than when it was last saved, i.e. a new duel caused it. A
-- different holder from partial data (a friend's stats not loaded yet, a
-- friend removed) is saved quietly. Test mode never saves or announces
-- (except /lp sim looserpiml).
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")

local Titles = {}
Stats.Titles = Titles

Titles.CHECK_DELAY = 1 -- seconds: many stats messages in a row, one check
Titles.holder = nil    -- full name of the current LooserPiml (for badges)

-- Current holder from all participants (all time): holder entry or nil,
-- plus the number of confirmed ranked duels.
function Titles:Current()
	local participants = Stats:GetParticipants("all")
	local merged = Stats.Ladder.Merge(participants)
	return Stats.Leaderboard.LooserPiml(participants, merged), #merged.confirmed
end

function Titles:Check(silent)
	local holder, confirmed = self:Current()
	local previousHolder = self.holder
	self.holder = holder and holder.name or nil
	if self.holder ~= previousHolder then
		ns.Events:Fire("LP_BADGES_CHANGED")
	end
	if ns.TestMode:IsEnabled() or not holder then
		return -- partial data or nobody qualifies: keep what was saved
	end
	local saved = Stats.db.looserPiml or {}
	local changed = saved.name ~= holder.name
	local newDuels = confirmed > (saved.confirmed or 0)
	Stats.db.looserPiml = { name = holder.name, confirmed = math.max(confirmed, saved.confirmed or 0) }
	if changed and newDuels and not silent then
		ns.Events:Fire("LP_LOOSERPIML_CHANGED", { name = holder.name, class = holder.class, previous = saved.name })
	end
end

function Titles:RequestCheck()
	if self.checkScheduled then
		return
	end
	self.checkScheduled = true
	C_Timer.After(self.CHECK_DELAY, function()
		self.checkScheduled = false
		if Stats:IsEnabled() then
			self:Check(false)
		end
	end)
end

-- /lp sim looserpiml <name>: the banner with a fake friend (nothing saved).
function Titles:Simulate(name)
	name = name or ns.TestMode.FAKE_MEMBERS[4].name
	local member = ns.Roster:GetMember(name)
	ns.Events:Fire("LP_LOOSERPIML_CHANGED", { name = ns.Roster:Normalize(name), class = member and member.class, test = true })
end

function Titles:Register()
	ns.Window:AddBadgeProvider(function(fullName)
		if Stats:IsEnabled() and Titles.holder ~= nil and fullName == Titles.holder then
			return L.LOOSERPIML_BADGE
		end
		return nil
	end)
end

-- Registered with Titles as owner: Stats already listens to these events
-- itself, and a second registration with the same owner would replace its
-- handler. Stats:OnDisable unregisters Titles too.
function Titles:Enable()
	for _, event in ipairs({ "LP_STATS_CHANGED", "LP_FRIENDS_CHANGED", "LP_FILL_SAMPLES" }) do
		ns.Events:Register(self, event, function()
			Titles:RequestCheck()
		end)
	end
	ns.TestMode:RegisterSim(Stats, { "looserpiml" }, function(_, _, name)
		Titles:Simulate(name)
	end)
	-- At login: who holds it now, without a banner (it may have changed
	-- while we were away, or this version is new).
	self:Check(true)
end
