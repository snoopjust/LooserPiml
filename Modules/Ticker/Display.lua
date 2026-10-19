-- Ticker display: a center-screen banner (queued, fading, class-colored
-- names) plus a local chat line. Nothing here is sent to anyone.
--
-- During a boss encounter banners are held and shown afterwards, prefixed
-- with "During the boss:".
--
-- Friends who enter or leave the same instance at about the same time get
-- one banner ("Max and Lootius entered The Deadmines."): enter/leave
-- events wait COMBINE_DELAY seconds for others.
--
-- Entries flagged chatOnly (setting "Ticker messages from friends: chat
-- line only") never become banners or play sounds.
local _, ns = ...
local L = ns.L

local Ticker = ns:GetModule("Ticker")

local Display = {}
Ticker.Display = Display

Display.HOLD = 4           -- default seconds a banner stays fully visible (setting: banner.hold)
Display.FADE = 0.5         -- seconds for fade in / fade out
Display.MAX_QUEUE = 10     -- waiting banners; older ones are dropped
Display.MAX_HELD_SHOWN = 5 -- after an encounter, show at most this many banners
Display.OFFSET_Y = 250     -- banner position above screen center
Display.WATCH_INTERVAL = 2 -- seconds; re-check while holding in case the end event got lost
Display.FONT_SIZE = 40     -- default (setting: banner.size); GameFontNormalHuge is only ~24, too easy to overlook
Display.COMBINE_DELAY = 2  -- seconds enter/leave events wait for friends doing the same

local function settings()
	return Ticker.db and Ticker.db.banner or {}
end

function Display:GetHold()
	return settings().hold or self.HOLD
end

-- Text color per variant (r, g, b). Class-colored names keep their own color.
Display.COLORS = {
	death = { 1, 0.35, 0.35 },
	death_again = { 1, 0.35, 0.35 },
	drowned = { 0.45, 0.75, 1 },
	levelup = { 1, 0.82, 0 },
	enter = { 0.85, 1, 0.85 },
	leave = { 0.85, 0.85, 0.85 },
	wishloot = { 0.9, 0.72, 0.36 },
	duel_ranked = { 1, 0.6, 0.2 },
	duel_fun = { 0.85, 0.85, 0.85 },
}

-- PlaySound takes a SoundKit ID; 8959 = raid warning, 888 = level-up fanfare.
-- Enter/leave stay silent. Sounds play on the "Master" channel so they work
-- even with sound effects muted. Confirmed in-game (TESTING.md #25).
Display.SOUNDS = {
	death = 8959,
	death_again = 8959,
	drowned = 8959,
	levelup = 888,
}

Display.queue = {}   -- entries waiting for the banner
Display.held = {}    -- entries held during an encounter
Display.pending = {} -- enter/leave events collecting names, by kind|instance|late|test
Display.showing = false

-- WoW fonts have no emoji glyphs, so icons are texture escapes.
-- Raid target icons exist in every client: 1 star, 2 circle, 4 triangle,
-- 6 square, 8 skull. Confirmed in-game (TESTING.md #16).
local function icon(index)
	return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
end
Display.ICONS = {
	death = icon(8),
	death_again = icon(8),
	drowned = icon(6),
	levelup = icon(1),
	enter = icon(4),
	leave = icon(2),
	wishloot = icon(3),
	duel_ranked = icon(7), -- cross; 7 and 5: TODO(verify in-game) like the others
	duel_fun = icon(5),    -- moon
}

-- Random variant picker; tests replace it to get deterministic output.
function Display.Pick(count)
	return math.random(count)
end

-- "Max", "Max and Lena", "Max, Lena and Jo"
function Display.JoinNames(names)
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, L.NAMES_SEPARATOR, 1, #names - 1) .. L.NAMES_AND .. names[#names]
end

-- Builds a display entry: { icon, text, variant }. nameText (optional)
-- replaces the sender's name, for combined entries.
function Display:Format(sender, data, nameText)
	local kind = data.k
	local variant = kind
	local count = Ticker.Stats:GetSessionDeaths(sender)
	if kind == "death" then
		if data.dr then
			variant = "drowned"
		elseif count > 1 then
			variant = "death_again"
		end
	end
	local templates = L.TICKER[variant]
	local template = templates[self.Pick(#templates)]
	local values = {
		name = nameText or ns.Roster:ColorName(sender, data.c),
		level = tostring(data.lvl or "?"),
		count = tostring(count),
		zone = data.z or L.UNKNOWN_PLACE,
		instance = data.i or L.UNKNOWN_PLACE,
	}
	if kind == "wishloot" then
		-- Prefer the receiver's own item cache (localized name); the sender's
		-- name (already escaped by Sanitize) is the fallback.
		local cached = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(data.id)
		local itemName = (type(cached) == "string" and not ns.IsSecret(cached)) and cached:gsub("|", "||") or data.nm or ("#" .. tostring(data.id))
		values.item = "|c" .. ns.Util.QualityHex(data.q) .. itemName .. "|r"
		values.count = tostring(data.n or 1)
		values.owner = (not data.o or ns.Roster:IsPlayer(data.o)) and L.WISH_OWNER_YOU or L.WISH_OWNER:format(ns.Roster:ColorName(data.o))
		values.need = (data.need or 0) > 0 and L.WISH_STILL_NEEDED:format(data.need) or L.WISH_ENOUGH
	elseif kind == "duel_ranked" or kind == "duel_fun" then
		values.opponent = ns.Roster:ColorName(data.o, data.oc)
		values.wins = tostring(data.w or 0)
		values.losses = tostring(data.l or 0)
		values.fled = data.fl and L.DUEL_FLED_SUFFIX:format(values.opponent) or ""
	end
	local text = template:gsub("{(%a+)}", values)
	return { icon = self.ICONS[variant], text = text, variant = variant }
end

-- icon [test] During the boss: text
function Display:Compose(entry)
	local text = entry.text
	if entry.late == "encounter" then
		text = L.DURING_BOSS:format(text)
	elseif entry.late == "lockdown" then
		text = L.EARLIER:format(text)
	end
	if entry.test then
		text = L.TEST_TAG .. " " .. text
	end
	if entry.icon then
		text = entry.icon .. " " .. text
	end
	return text
end

-- opts: test (simulated), late ("encounter" | "lockdown": sender held it
-- back), chatOnly (no banner, no sound)
function Display:ShowEvent(sender, data, opts)
	opts = opts or {}
	if data.k == "duel_fun" then
		opts.chatOnly = true -- fun duels never get a banner
	end
	if (data.k == "enter" or data.k == "leave") and data.i then
		return self:Collect(sender, data, opts)
	end
	return self:Show(self:Format(sender, data), opts)
end

-- Enter/leave: the first event of a kind + instance waits COMBINE_DELAY
-- seconds; friends doing the same meanwhile join its banner. A banner is
-- shown if any of them wants one.
function Display:Collect(sender, data, opts)
	local key = table.concat({ data.k, data.i, tostring(opts.late), tostring(opts.test) }, "|")
	local batch = self.pending[key]
	if batch then
		if not batch.senders[sender] then
			batch.senders[sender] = true
			batch.names[#batch.names + 1] = ns.Roster:ColorName(sender, data.c)
		end
		batch.chatOnly = batch.chatOnly and opts.chatOnly
		return "combined"
	end
	batch = {
		sender = sender,
		data = data,
		opts = opts,
		chatOnly = opts.chatOnly,
		senders = { [sender] = true },
		names = { ns.Roster:ColorName(sender, data.c) },
	}
	self.pending[key] = batch
	C_Timer.After(self.COMBINE_DELAY, function()
		self.pending[key] = nil
		local entry = self:Format(batch.sender, batch.data, Display.JoinNames(batch.names))
		self:Show(entry, { test = batch.opts.test, late = batch.opts.late, chatOnly = batch.chatOnly })
	end)
	return "collecting"
end

function Display:Show(entry, opts)
	entry.test = opts.test
	entry.late = opts.late
	entry.chatOnly = opts.chatOnly
	if ns.Events:IsEncounterActive() then
		self.held[#self.held + 1] = entry
		self:WatchEncounter()
		return "held"
	end
	if entry.chatOnly then
		self:PrintChat(self:Compose(entry))
		return "chat"
	end
	self:Enqueue(entry)
	return "queued"
end

-- While holding: poll, so banners still come out if no LP_ENCOUNTER_END
-- arrives (lost event, restriction ended without an encounter event).
function Display:WatchEncounter()
	if self.watch then
		return
	end
	self.watch = C_Timer.NewTicker(self.WATCH_INTERVAL, function()
		if not ns.Events:IsEncounterActive() then
			self:OnEncounterEnd()
		end
	end)
end

function Display:Enqueue(entry)
	self:PrintChat(self:Compose(entry))
	self.queue[#self.queue + 1] = entry
	while #self.queue > self.MAX_QUEUE do
		table.remove(self.queue, 1)
	end
	if not self.showing then
		self:ShowNext()
	end
end

function Display:ShowNext()
	if ns.Events:IsEncounterActive() then
		self.showing = false -- resumes after the encounter
		self:WatchEncounter()
		return
	end
	local entry = table.remove(self.queue, 1)
	if not entry then
		self.showing = false
		return
	end
	self.showing = true
	self:Render(self:Compose(entry), entry.variant)
	self:PlaySound(entry.variant)
	C_Timer.After(self:GetHold() + 2 * self.FADE, function()
		self:ShowNext()
	end)
end

function Display:OnEncounterStart()
	-- Banners already waiting stay queued; ShowNext pauses until the end.
end

function Display:OnEncounterEnd()
	if self.watch then
		self.watch:Cancel()
		self.watch = nil
	end
	if ns.Events:IsEncounterActive() then
		self:WatchEncounter() -- the client still reports a fight (next pull?)
		return
	end
	local held, chatOnly = {}, {}
	for _, entry in ipairs(self.held) do
		entry.late = "encounter"
		if entry.chatOnly then
			chatOnly[#chatOnly + 1] = entry
		else
			held[#held + 1] = entry
		end
	end
	self.held = {}
	for _, entry in ipairs(chatOnly) do
		self:PrintChat(self:Compose(entry))
	end
	if Ticker.db and Ticker.db.show and Ticker.db.show.bossRecap == false then
		-- Recap switched off: keep the record in chat, no banners.
		for _, entry in ipairs(held) do
			entry.late = "encounter"
			self:PrintChat(self:Compose(entry))
		end
		return
	end
	for i, entry in ipairs(held) do
		entry.late = "encounter"
		if i <= self.MAX_HELD_SHOWN then
			self:Enqueue(entry)
		else
			self:PrintChat(self:Compose(entry))
		end
	end
	if #held > self.MAX_HELD_SHOWN then
		self:Enqueue({ text = L.HELD_MORE:format(#held - self.MAX_HELD_SHOWN) })
	end
	if not self.showing then
		self:ShowNext()
	end
end

-- Played when the banner appears (not when queued, so it matches what you
-- see, and not during a boss fight). Local output only.
function Display:PlaySound(variant)
	local id = self.SOUNDS[variant]
	if not id or not PlaySound or settings().sound == false then
		return
	end
	PlaySound(id, "Master")
end

function Display:PrintChat(text)
	if Ticker.db and Ticker.db.chatLog == false then
		return
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(L.CHAT_TAG .. " " .. text)
	end
end

----------------------------------------------------------------------
-- Banner frame
----------------------------------------------------------------------

function Display:GetFrame()
	if self.frame then
		return self.frame
	end
	-- Parented to UIParent so it hides with the UI (Alt+Z) and scales with
	-- it. Strata HIGH puts it above the game UI but below dialogs.
	-- EnableMouse(false) makes it click-through: it must never eat a click
	-- in the middle of the screen (only while "Move banner" is active).
	local frame = CreateFrame("Frame", "LooserPimlBanner", UIParent)
	frame:SetSize(1600, 100)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(false)
	frame:Hide()

	-- Shown only while unlocked, so you can see what you are dragging.
	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.1, 0.08, 0.06, 0.6)
	background:Hide()
	frame.background = background

	-- GameFontNormalHuge is a font object from Blizzard's UI code (confirmed
	-- in-game, TESTING.md #16).
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("CENTER")
	text:SetWidth(1600)
	text:SetJustifyH("CENTER")
	text:SetTextColor(1, 1, 1)
	text:SetShadowOffset(2, -2)
	frame.text = text
	-- Keep the template's font file (it follows the client locale); only the
	-- size and outline change.
	frame.fontPath = text:GetFont()

	-- An AnimationGroup fades in, holds and fades out without any OnUpdate code.
	local anim = frame:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(self.FADE)
	fadeIn:SetOrder(1)
	local hold = anim:CreateAnimation("Alpha")
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)
	hold:SetOrder(2)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(self.FADE)
	fadeOut:SetOrder(3)
	anim:SetScript("OnFinished", function()
		if not self.unlocked then
			frame:Hide()
		end
	end)
	frame.anim = anim
	frame.holdAnim = hold

	frame:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	frame:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		self:SavePosition()
	end)

	self.frame = frame
	self:ApplyPosition()
	self:ApplyStyle()
	return frame
end

-- Size and display time from the settings (also called when they change).
function Display:ApplyStyle()
	local frame = self.frame
	if not frame then
		return
	end
	if frame.fontPath then
		frame.text:SetFont(frame.fontPath, settings().size or self.FONT_SIZE, "THICKOUTLINE")
	end
	frame.holdAnim:SetDuration(self:GetHold())
end

function Display:ApplyPosition()
	local frame = self.frame
	if not frame then
		return
	end
	frame:ClearAllPoints()
	local point = settings().point
	if type(point) == "table" and point[1] then
		frame:SetPoint(point[1], UIParent, point[2] or point[1], point[3] or 0, point[4] or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, self.OFFSET_Y)
	end
end

function Display:SavePosition()
	local point, _, relativePoint, x, y = self.frame:GetPoint(1)
	if point and Ticker.db then
		Ticker.db.banner.point = { point, relativePoint, x, y }
	end
end

function Display:ResetPosition()
	if Ticker.db then
		Ticker.db.banner.point = nil
	end
	self:ApplyPosition()
end

-- "Move banner": unlocked shows a sample banner you can drag; locking
-- makes it click-through again.
function Display:SetUnlocked(unlocked)
	local frame = self:GetFrame()
	self.unlocked = unlocked and true or false
	frame:SetMovable(self.unlocked)
	frame:EnableMouse(self.unlocked)
	if self.unlocked then
		frame:RegisterForDrag("LeftButton")
		frame.anim:Stop()
		frame.background:Show()
		frame.text:SetText(L.BANNER_MOVE_HINT)
		frame:SetAlpha(1)
		frame:Show()
	else
		frame:RegisterForDrag()
		frame.background:Hide()
		frame:Hide()
	end
end

function Display:ToggleUnlocked()
	self:SetUnlocked(not self.unlocked)
	ns.Log:Print(self.unlocked and L.BANNER_UNLOCKED or L.BANNER_LOCKED)
end

function Display:Render(text, variant)
	local frame = self:GetFrame()
	if self.unlocked then
		return -- while moving, the sample banner stays
	end
	frame.anim:Stop()
	local color = self.COLORS[variant] or { 1, 1, 1 }
	frame.text:SetTextColor(color[1], color[2], color[3])
	frame.text:SetText(text)
	frame:Show()
	frame.anim:Play()
end
