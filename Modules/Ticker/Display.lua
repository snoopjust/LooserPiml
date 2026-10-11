-- Ticker display: a center-screen banner (queued, fading, class-colored
-- names) plus a local chat line. Nothing here is sent to anyone.
--
-- During a boss encounter banners are held and shown afterwards, prefixed
-- with "During the boss:".
local _, ns = ...
local L = ns.L

local Ticker = ns:GetModule("Ticker")

local Display = {}
Ticker.Display = Display

Display.HOLD = 4           -- seconds a banner stays fully visible
Display.FADE = 0.5         -- seconds for fade in / fade out
Display.MAX_QUEUE = 10     -- waiting banners; older ones are dropped
Display.MAX_HELD_SHOWN = 5 -- after an encounter, show at most this many banners
Display.OFFSET_Y = 220     -- banner position above screen center
Display.WATCH_INTERVAL = 2 -- seconds; re-check while holding in case the end event got lost

Display.queue = {} -- entries waiting for the banner
Display.held = {}  -- entries held during an encounter
Display.showing = false

-- WoW fonts have no emoji glyphs, so icons are texture escapes.
-- Raid target icons exist in every client: 1 star, 2 circle, 4 triangle,
-- 6 square, 8 skull. TODO(verify in-game): icons render in Forever.
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
}

-- Random variant picker; tests replace it to get deterministic output.
function Display.Pick(count)
	return math.random(count)
end

-- Builds a display entry: { icon, text, test, late }
function Display:Format(sender, data)
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
		name = ns.Roster:ColorName(sender, data.c),
		level = tostring(data.lvl or "?"),
		count = tostring(count),
		zone = data.z or L.UNKNOWN_PLACE,
		instance = data.i or L.UNKNOWN_PLACE,
	}
	local text = template:gsub("{(%a+)}", values)
	return { icon = self.ICONS[variant], text = text }
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

-- opts: test (simulated), late ("encounter" | "lockdown": sender held it back)
function Display:ShowEvent(sender, data, opts)
	opts = opts or {}
	local entry = self:Format(sender, data)
	entry.test = opts.test
	entry.late = opts.late
	if ns.Events:IsEncounterActive() then
		self.held[#self.held + 1] = entry
		self:WatchEncounter()
		return "held"
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
	self:Render(self:Compose(entry))
	C_Timer.After(self.HOLD + 2 * self.FADE, function()
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
	local held = self.held
	self.held = {}
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
	local frame = CreateFrame("Frame", "LooserPimlBanner", UIParent)
	frame:SetSize(1000, 60)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, self.OFFSET_Y)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(false)
	frame:Hide()

	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("CENTER")
	text:SetWidth(1000)
	text:SetJustifyH("CENTER")
	text:SetTextColor(1, 1, 1)
	frame.text = text

	local anim = frame:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(self.FADE)
	fadeIn:SetOrder(1)
	local hold = anim:CreateAnimation("Alpha")
	hold:SetFromAlpha(1)
	hold:SetToAlpha(1)
	hold:SetDuration(self.HOLD)
	hold:SetOrder(2)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(self.FADE)
	fadeOut:SetOrder(3)
	anim:SetScript("OnFinished", function()
		frame:Hide()
	end)
	frame.anim = anim

	self.frame = frame
	return frame
end

function Display:Render(text)
	local frame = self:GetFrame()
	frame.anim:Stop()
	frame.text:SetText(text)
	frame:Show()
	frame.anim:Play()
end
