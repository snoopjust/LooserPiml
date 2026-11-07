-- Reminds the player to save (/reload), so a game crash doesn't take the
-- friends list and the evening's stats with it.
--
-- WoW writes every addon's SavedVariables only on logout, character switch,
-- /reload and a normal exit. After a crash everything since the last of
-- those is gone (seen on launch weekend 2026-11-06: a crash lost the
-- freshly added friends). An addon can't save on its own; it can only ask.
--
-- So, at a quiet moment (not in combat, not in an instance or boss fight):
--   - right after a friend was added: "save now?"
--   - otherwise every INTERVAL minutes since login or the last /reload.
-- The prompt is LooserPiml's own dialog. Only its "Reload now" button
-- reloads (C_UI.Reload / ReloadUI, which Blizzard's Forever UI code
-- lists without restrictions); LooserPiml never reloads on its own.
-- Setting: "Remind me to save (/reload)" in the LooserPiml friends section.
local _, ns = ...
local L = ns.L

local SaveReminder = {}
ns:RegisterCore("SaveReminder", SaveReminder)

SaveReminder.INTERVAL = 60 * 60   -- seconds between reminders
SaveReminder.LATER = 20 * 60      -- "Later" asks again after this long
SaveReminder.CHECK_EVERY = 30     -- seconds between quiet-moment checks
SaveReminder.DIALOG = "LOOSERPIML_SAVE"

function SaveReminder:IsOn()
	return ns.DB:Get("saveReminder") ~= false
end

-- Not now: fighting, in a dungeon / raid / battleground (a reload there
-- means a loading screen mid-run), during a boss, or while dead.
function SaveReminder:IsQuietMoment()
	if InCombatLockdown and InCombatLockdown() then
		return false
	end
	if ns.Events:IsEncounterActive() then
		return false
	end
	if IsInInstance then
		local inInstance = IsInInstance()
		if ns.IsSecret(inInstance) or inInstance then
			return false
		end
	end
	if UnitIsDeadOrGhost then
		local dead = UnitIsDeadOrGhost("player")
		if ns.IsSecret(dead) or dead then
			return false
		end
	end
	return true
end

-- Something worth saving happened (a friend added): ask at the next quiet
-- moment instead of waiting for the interval.
function SaveReminder:OnImportantChange(reason)
	self.pendingReason = reason or "friends"
end

function SaveReminder:Due(now)
	if self.pendingReason then
		return true
	end
	return now - (self.savedAt or now) >= self.INTERVAL
end

function SaveReminder:Check()
	if not self:IsOn() or self.showing or ns.TestMode:IsEnabled() then
		return
	end
	local now = GetTime()
	if not self:Due(now) or not self:IsQuietMoment() then
		return
	end
	self:Prompt(self.pendingReason == "friends" and L.SAVE_PROMPT_FRIENDS or L.SAVE_PROMPT)
end

function SaveReminder:Reload()
	if C_UI and C_UI.Reload then
		C_UI.Reload()
	elseif ReloadUI then
		ReloadUI()
	end
end

function SaveReminder:Later()
	self.showing = false
	self.pendingReason = nil
	-- Ask again LATER seconds from now.
	self.savedAt = GetTime() - self.INTERVAL + self.LATER
end

-- Our own StaticPopup (Blizzard's standard dialog frame, like the reset
-- confirmation in Core/Options.lua). Falls back to a chat line.
function SaveReminder:Prompt(text)
	ns.Log:Print(L.SAVE_CHAT_HINT)
	if not (StaticPopupDialogs and StaticPopup_Show) then
		self:Later()
		return
	end
	StaticPopupDialogs[self.DIALOG] = {
		text = text,
		button1 = L.SAVE_NOW,
		button2 = L.SAVE_LATER,
		OnAccept = function()
			-- The player's own click: the only place LooserPiml reloads.
			SaveReminder.showing = false
			SaveReminder:Reload()
		end,
		OnCancel = function()
			SaveReminder:Later()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	self.showing = true
	StaticPopup_Show(self.DIALOG)
end

function SaveReminder:OnInitialize()
	local Options = ns.Options
	Options:AddSection("friends", L.OPT_SECTION_FRIENDS, 5)
	Options:Add("friends", {
		type = "checkbox", key = "save.reminder", label = L.OPT_SAVE_REMINDER, tooltip = L.OPT_SAVE_REMINDER_TIP, default = true,
		get = function()
			return self:IsOn()
		end,
		set = function(value)
			ns.DB:Set("saveReminder", value and true or false)
		end,
	})
end

function SaveReminder:OnEnable()
	-- PLAYER_LOGIN runs after every login and /reload: the data was just
	-- saved (or loaded), so the clock starts now.
	self.savedAt = GetTime()
	self.pendingReason = nil
	self.showing = false
	self.ticker = C_Timer.NewTicker(self.CHECK_EVERY, function()
		self:Check()
	end)
end
