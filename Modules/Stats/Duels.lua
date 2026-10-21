-- Ranked duels between LooserPiml friends: the "ranked?" handshake, the own
-- record per opponent and the list of own ranked duels that travels with the
-- STATS message (Ladder.lua merges both sides into the ladder).
--
-- LooserPiml never takes part in the duel itself. It never calls
-- StartDuel, AcceptDuel, CancelDuel or ForfeitDuel and never touches
-- Blizzard's duel dialog (no click, no hide). It only notices what the
-- player does (hooksecurefunc post-hooks, DUEL_* events) and exchanges one
-- choice per player, as a whisper to the opponent only. Accepting or
-- declining stays in the game's own dialog.
--
-- Flow, A challenges B (both connected LooserPiml friends, grouped or not):
--   A  StartDuel post-hook     panel "waiting for B" (no duel id yet)
--   B  DUEL_REQUESTED(A)       new duel id, panel, DUEL ask -> A
--   A  ask                     adopts the id (opens the panel if the hook
--                              missed the request, e.g. another UI path)
--   both  Ranked / Just for fun  DUEL pick -> the other
--   B  AcceptDuel post-hook    DUEL start -> A; both panels close after the
--                              countdown
--   result (PvP.lua)           ranked only if both picked Ranked before the
--                              result line; recorded with the shared id
--   CancelDuel post-hook or DUEL_FINISHED before the start: closed, the
--   choice is gone. After a started duel the choice expires with the result
--   (or RESULT_GRACE after DUEL_FINISHED if no result line comes).
-- Opponent not a connected LooserPiml friend: no panel, no message, the
-- duel is a normal duel.
--
-- DUEL payload: a = "ask" | "pick" | "start" | "close", i = duel id,
--               p = "ranked" | "fun" | "off" ("off": doesn't ask for ranked)
--
-- Storage (own character, see Stats.lua):
--   char.duelRecord[opponent] = { w, l, rw, rl, s }   all / ranked wins and
--                               losses, s = ranked streak (+3 = W3, -2 = L2)
--   char.rankedDuels = { { i = id, t = time, o = opponent, w = won }, ... }
local _, ns = ...
local L = ns.L

local Stats = ns:GetModule("Stats")

local Duels = {}
Stats.Duels = Duels

Duels.MSG = "DUEL"
-- Seconds between accepting and the fight. The game counts down 3 s before
-- a duel starts ("Duel starting: 3 / 2 / 1", seen in-game 2026-10-20);
-- there is no event for the start itself, so the panel stays open for the
-- countdown after the accept.
Duels.COUNTDOWN = 3
-- DUEL_FINISHED and the result line (CHAT_MSG_SYSTEM) come close together;
-- their order is TODO(verify in-game), so the choice waits this long.
Duels.RESULT_GRACE = 5
-- An unanswered request: Blizzard's duel dialog times out after 60 s
-- (StaticPopupTimeoutSec) and calls CancelDuel, like Decline and Escape, so
-- our CancelDuel post-hook closes the panel; this is only the safety net.
Duels.REQUEST_TIMEOUT = 120
Duels.MAX_RANKED = 200 -- own ranked duels kept
Duels.MAX_SYNC = 60    -- ... and sent with STATS (newest first)
Duels.MAX_OPPONENTS = 40
Duels.ID_LENGTH = 8
Duels.CHOICES = { ranked = true, fun = true, off = true }
Duels.ACTIONS = { ask = true, pick = true, start = true, close = true }
-- /lp sim duel: seconds from your pick to the simulated accept, from the
-- request to the accept when you never pick, and from the accept to the
-- result (the panel closes after COUNTDOWN in between).
Duels.SIM_ACCEPT_DELAY = 2
Duels.SIM_NO_PICK = 30
Duels.SIM_FIGHT = 5

Duels.current = nil -- the pending duel: { opponent, role, id, mine, theirs, accepted, finished, test }
Duels.generation = 0

-- Class of a friend for name coloring: from the group if grouped, else
-- what the friends list remembered from their handshake.
function Duels.ClassOf(name)
	local class = ns.Roster:GetClass(name)
	if class then
		return class
	end
	local entry = ns.Friends:GetDB()[name]
	return entry and entry.class
end

local function newId()
	local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	local out = {}
	for i = 1, Duels.ID_LENGTH do
		local n = math.random(1, #chars)
		out[i] = chars:sub(n, n)
	end
	return table.concat(out)
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------

function Duels:IsAsking()
	return Stats:IsCollecting() and Stats.db.askRanked ~= false
end

function Duels:RegisterOptions()
	local Options = ns.Options
	-- Shown with the ticker settings (AddSection is idempotent).
	Options:AddSection("ticker", L.OPT_SECTION_TICKER, 10)
	Options:Add("ticker", {
		type = "checkbox", key = "duels.ask", label = L.OPT_DUEL_ASK, tooltip = L.OPT_DUEL_ASK_TIP, default = true,
		get = function()
			return Stats.db.askRanked ~= false
		end,
		set = function(value)
			Stats.db.askRanked = value and true or false
		end,
	})
end

----------------------------------------------------------------------
-- Own records
----------------------------------------------------------------------

function Duels:GetRecords()
	local char = Stats:GetChar()
	char.duelRecord = char.duelRecord or {}
	char.rankedDuels = char.rankedDuels or {}
	return char.duelRecord, char.rankedDuels
end

-- { w, l, rw, rl, s } against one opponent (zeros if none).
function Duels:GetRecord(opponent)
	local records = self:GetRecords()
	return records[opponent] or { w = 0, l = 0, rw = 0, rl = 0, s = 0 }
end

-- result: "won" | "lost" | "fled" | "opponent_fled" (Stats:ParseDuel).
-- Fled counts as a loss for whoever fled.
function Duels:RecordResult(result, opponent, ranked, id)
	local records, rankedList = self:GetRecords()
	local won = result == "won" or result == "opponent_fled"
	local record = records[opponent] or { w = 0, l = 0, rw = 0, rl = 0, s = 0 }
	records[opponent] = record
	if won then
		record.w = record.w + 1
	else
		record.l = record.l + 1
	end
	if ranked then
		if won then
			record.rw = record.rw + 1
			record.s = record.s > 0 and record.s + 1 or 1
		else
			record.rl = record.rl + 1
			record.s = record.s < 0 and record.s - 1 or -1
		end
		rankedList[#rankedList + 1] = { i = id, t = GetServerTime(), o = opponent, w = won }
		while #rankedList > self.MAX_RANKED do
			table.remove(rankedList, 1)
		end
	end
	return record, won
end

-- What goes out with STATS: the newest ranked duels and the record against
-- each opponent, both only for opponents on the LooserPiml friends list
-- (strangers' names never leave the client). nil when there is nothing.
-- { r = { { i, t, o, w }, ... }, h = { [opponent] = { w, l, rw, rl } } }
function Duels:ForSync()
	local records, rankedList = self:GetRecords()
	local r, h, count = {}, {}, 0
	for i = #rankedList, 1, -1 do
		local duel = rankedList[i]
		if #r >= self.MAX_SYNC then
			break
		end
		if ns.Friends:IsListed(duel.o) then
			r[#r + 1] = { i = duel.i, t = duel.t, o = duel.o, w = duel.w }
		end
	end
	local names = {}
	for name in pairs(records) do
		if ns.Friends:IsListed(name) then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		if count >= self.MAX_OPPONENTS then
			break
		end
		local record = records[name]
		h[name] = { w = record.w, l = record.l, rw = record.rw, rl = record.rl }
		count = count + 1
	end
	if #r == 0 and count == 0 then
		return nil
	end
	return { r = r, h = h }
end

-- My own data in the same shape, for the ladder on my screen (no friends
-- filter needed: the ladder only pairs participants anyway).
function Duels:Own()
	local records, rankedList = self:GetRecords()
	local h = {}
	for name, record in pairs(records) do
		h[name] = { w = record.w, l = record.l, rw = record.rw, rl = record.rl }
	end
	return { r = rankedList, h = h }
end

local function cleanName(value)
	if type(value) ~= "string" or value == "" or #value > 64 or not value:find("^[^|%s]+$") then
		return nil
	end
	return ns.Roster:Normalize(value)
end

local function cleanCount(value)
	if type(value) ~= "number" or value ~= value or value < 0 or value > 1000000 then
		return 0
	end
	return math.floor(value)
end

-- Untrusted duel data from a friend's STATS message.
function Duels.Clean(data)
	if type(data) ~= "table" then
		return nil
	end
	local out = { r = {}, h = {} }
	if type(data.r) == "table" then
		for _, duel in ipairs(data.r) do
			if #out.r >= Duels.MAX_SYNC then
				break
			end
			if type(duel) == "table" and type(duel.i) == "string" and #duel.i <= 16 and duel.i:find("^%w+$")
				and type(duel.t) == "number" and duel.t == duel.t and duel.t >= 0 and duel.t <= 1e10
				and type(duel.w) == "boolean" then
				local opponent = cleanName(duel.o)
				if opponent then
					out.r[#out.r + 1] = { i = duel.i, t = math.floor(duel.t), o = opponent, w = duel.w }
				end
			end
		end
	end
	if type(data.h) == "table" then
		local count = 0
		for name, record in pairs(data.h) do
			local opponent = cleanName(name)
			if opponent and type(record) == "table" then
				count = count + 1
				if count > Duels.MAX_OPPONENTS then
					break
				end
				out.h[opponent] = { w = cleanCount(record.w), l = cleanCount(record.l), rw = cleanCount(record.rw), rl = cleanCount(record.rl) }
			end
		end
	end
	return out
end

----------------------------------------------------------------------
-- The pending duel
----------------------------------------------------------------------

function Duels:Begin(opponent, role, id, test)
	self.generation = self.generation + 1
	self.current = { opponent = opponent, role = role, id = id, test = test, generation = self.generation }
	local generation = self.generation
	C_Timer.After(self.REQUEST_TIMEOUT, function()
		local cur = self.current
		if cur and cur.generation == generation and not cur.accepted then
			self:End("timeout")
		end
	end)
	Stats.DuelPanel:Open(self.current)
	return self.current
end

function Duels:End(reason)
	if not self.current then
		return
	end
	ns.Log:Debug("Duel with %s closed (%s)", tostring(self.current.opponent), tostring(reason))
	self.current = nil
	Stats.DuelPanel:Close()
end

function Duels:Matches(sender, id)
	local cur = self.current
	return cur ~= nil and cur.opponent == sender and (id == nil or cur.id == nil or cur.id == id)
end

-- Only to the opponent, as a whisper (Comm routes it; it reaches them only
-- if they are a connected LooserPiml friend).
function Duels:SendTo(opponent, action, id, choice)
	return ns.Comm:Send(self.MSG, { a = action, i = id, p = choice }, { scope = "friends", to = { opponent } })
end

function Duels:Send(action, choice)
	local cur = self.current
	if cur then
		return self:SendTo(cur.opponent, action, cur.id, choice)
	end
end

-- The player clicked Ranked or Just for fun in our panel.
function Duels:Pick(choice)
	local cur = self.current
	if not cur or (choice ~= "ranked" and choice ~= "fun") then
		return
	end
	cur.mine = choice
	self:Send("pick", choice)
	Stats.DuelPanel:Refresh(cur)
	if cur.sim then
		self:SimAccept(cur, self.SIM_ACCEPT_DELAY)
	end
end

-- "Both picked Ranked before the duel ended."
function Duels:IsRanked(cur)
	return cur ~= nil and cur.id ~= nil and cur.mine == "ranked" and cur.theirs == "ranked"
end

-- Accepted: the panel stays for the countdown, then closes. The choice
-- itself stays valid until the result.
function Duels:OnStarted()
	local cur = self.current
	if not cur or cur.accepted then
		return
	end
	cur.accepted = true
	local generation = cur.generation
	C_Timer.After(self.COUNTDOWN, function()
		if self.current and self.current.generation == generation then
			Stats.DuelPanel:Close()
		end
	end)
end

----------------------------------------------------------------------
-- What the player and the game do
----------------------------------------------------------------------

-- StartDuel(unit or name [, exactMatch [, toTheDeath]]). Blizzard's Forever
-- UI code (1.60.1): the unit menu calls StartDuel(unit, true), /duel calls
-- StartDuel(msg) with a name or "" (= target), and a duel to the death
-- (hardcore) StartDuel(unit, true, true). Unit names can be secret; then we
-- don't know the opponent and wait for their client's ask instead.
function Duels:ResolveTarget(arg)
	if arg == nil or arg == "" then
		arg = "target"
	end
	if type(arg) ~= "string" or ns.IsSecret(arg) then
		return nil
	end
	if UnitExists and UnitExists(arg) then
		local name, realm = UnitName(arg)
		if type(name) ~= "string" or ns.IsSecret(name) or ns.IsSecret(realm) then
			return nil
		end
		if type(realm) == "string" and realm ~= "" then
			name = name .. "-" .. realm
		end
		return ns.Roster:Normalize(name)
	end
	-- /duel <name>: may be typed without the surname.
	return cleanName(arg) and ns.Friends:Resolve(arg)
end

-- Duels to the death are left alone: the challenged side gets
-- DUEL_TO_THE_DEATH_REQUESTED, not DUEL_REQUESTED, so there would never be
-- an answer to a ranked question.
function Duels:OnStartDuel(arg, toTheDeath)
	if toTheDeath then
		return
	end
	local opponent = self:ResolveTarget(arg)
	if not opponent or not self:IsAsking() or not ns.Friends:IsConnected(opponent) then
		return
	end
	if self.current and self.current.opponent == opponent then
		return
	end
	self:Begin(opponent, "challenger", nil)
end

-- DUEL_REQUESTED: payload playerName (cstring, Forever API docs). On the
-- megaserver probably "First Surname" like the result line; Resolve also
-- takes a bare first name. TODO(verify in-game): the exact shape.
function Duels:OnDuelRequested(_, name)
	if type(name) ~= "string" or ns.IsSecret(name) then
		return
	end
	local opponent = ns.Friends:Resolve(name)
	if not opponent or not ns.Friends:IsConnected(opponent) then
		return -- not a connected LooserPiml friend: a normal duel, nothing is sent
	end
	if not self:IsAsking() then
		-- Tell their panel right away instead of letting it wait.
		self:SendTo(opponent, "ask", nil, "off")
		return
	end
	self:Begin(opponent, "challenged", newId())
	self:Send("ask")
end

-- AcceptDuel post-hook: the challenged player clicked Accept in Blizzard's
-- dialog.
function Duels:OnAcceptDuel()
	local cur = self.current
	if cur and cur.role == "challenged" and not cur.accepted then
		self:Send("start")
		self:OnStarted()
	end
end

-- CancelDuel post-hook: declined (challenged) or withdrawn (challenger)
-- before the duel started.
function Duels:OnCancelDuel()
	local cur = self.current
	if cur and not cur.accepted then
		self:Send("close")
		self:End("cancelled")
	end
end

-- DUEL_FINISHED: the request was declined, withdrawn or timed out, or the
-- duel is over.
function Duels:OnDuelFinished()
	local cur = self.current
	if not cur or cur.test then
		return
	end
	if not cur.accepted then
		self:End("declined")
		return
	end
	cur.finished = true
	local generation = cur.generation
	C_Timer.After(self.RESULT_GRACE, function()
		if self.current and self.current.generation == generation then
			self:End("expired")
		end
	end)
end

-- Called by PvP.lua for every own duel result. Returns ranked, id and
-- ends the pending duel with that opponent (the choice expires now).
function Duels:TakeResult(opponent)
	local cur = self.current
	if not cur or cur.opponent ~= opponent then
		return false, nil
	end
	local ranked, id = self:IsRanked(cur), cur.id
	self:End("result")
	return ranked, ranked and id or nil
end

-- After the result was recorded: tell the Ticker (duels between LooserPiml
-- friends only; the winner's client announces it).
function Duels:Announce(result, opponent, ranked, record, won, test)
	if not ns.Friends:IsListed(opponent) and not test then
		return
	end
	ns.Events:Fire("LP_DUEL_RESULT", {
		o = opponent,
		oc = Duels.ClassOf(opponent),
		won = won,
		fled = result == "fled" or result == "opponent_fled",
		ranked = ranked and true or false,
		rw = record.rw,
		rl = record.rl,
		test = test,
	})
end

----------------------------------------------------------------------
-- Messages from the opponent
----------------------------------------------------------------------

function Duels:OnMessage(data, sender, meta)
	if type(data) ~= "table" or not self.ACTIONS[data.a] then
		return
	end
	local id = type(data.i) == "string" and #data.i <= 16 and data.i:find("^%w+$") and data.i or nil
	local choice = self.CHOICES[data.p] and data.p or nil
	local action = data.a
	if action == "ask" then
		self:OnAsk(sender, id, choice, meta)
		return
	end
	if not self:Matches(sender, id) then
		return -- an old message, or about a duel we don't know
	end
	local cur = self.current
	if action == "pick" then
		cur.id = cur.id or id
		cur.theirs = choice
		Stats.DuelPanel:Refresh(cur)
	elseif action == "start" then
		self:OnStarted()
	elseif action == "close" then
		self:End("closed by " .. sender)
	end
end

-- The challenged friend's client saw our request (or says it doesn't ask).
function Duels:OnAsk(sender, id, choice, meta)
	local cur = self.current
	if choice == "off" then
		if cur and cur.opponent == sender then
			cur.theirs = "off"
			Stats.DuelPanel:Refresh(cur)
		end
		return
	end
	if not id then
		return
	end
	if not self:IsAsking() then
		self:SendTo(sender, "pick", id, "off")
		return
	end
	if cur and cur.opponent == sender and (cur.id == nil or cur.id == id) then
		cur.id = id
		if cur.mine then
			self:Send("pick", cur.mine) -- picked before the ask arrived: now with the id
		end
		Stats.DuelPanel:Refresh(cur)
		return
	end
	if cur and not cur.accepted then
		self:End("superseded")
	elseif cur then
		return -- busy with a running duel
	end
	self:Begin(sender, "challenger", id, meta.test)
end

----------------------------------------------------------------------
-- Test mode: /lp sim duel <name> ranked|fun|fled
----------------------------------------------------------------------

-- A fake friend challenges you: the panel opens, their pick arrives after
-- 1 s ("fun": Just for fun, otherwise Ranked). The sim waits for your own
-- pick (or SIM_NO_PICK s without one), then "accepts" after
-- SIM_ACCEPT_DELAY s; the panel closes after the countdown and you win
-- SIM_FIGHT s after the accept ("fled": they flee).
-- Nothing is recorded and nothing leaves the client.
function Duels:Simulate(name, mode)
	if not name then
		name = ns.TestMode.FAKE_MEMBERS[1].name
	end
	mode = (mode == "fun" or mode == "fled") and mode or "ranked"
	local opponent = ns.Roster:Normalize(name)
	self:End("new simulation")
	local cur = self:Begin(opponent, "challenged", newId(), true)
	cur.sim = { name = name, mode = mode }
	local generation = cur.generation
	C_Timer.After(1, function()
		if self.current and self.current.generation == generation then
			ns.Comm:SimulateReceive(name, self.MSG, { a = "pick", i = cur.id, p = mode == "fun" and "fun" or "ranked" })
		end
	end)
	self:SimAccept(cur, self.SIM_NO_PICK)
end

-- The simulated accept (once per simulated duel), then the result.
function Duels:SimAccept(cur, delay)
	C_Timer.After(delay, function()
		if self.current ~= cur or cur.sim.accepted then
			return
		end
		cur.sim.accepted = true
		self:OnStarted()
		C_Timer.After(self.SIM_FIGHT, function()
			if self.current ~= cur then
				return
			end
			local ranked = self:IsRanked(cur)
			self:End("simulated result")
			local member = ns.Roster:GetMember(cur.sim.name)
			local record = self:GetRecord(cur.opponent)
			ns.Events:Fire("LP_DUEL_RESULT", {
				o = cur.opponent,
				oc = member and member.class,
				won = true,
				fled = cur.sim.mode == "fled",
				ranked = ranked,
				rw = record.rw + (ranked and 1 or 0),
				rl = record.rl,
				test = true,
			})
		end)
	end)
end

-- Sample duels between the four fake friends (names[1..4]) for the PvP tab
-- in test mode: both sides' records, one duel disputed. name -> duel data.
function Duels.SampleData(names, now)
	local max, lena, jo, kim = names[1], names[2], names[3], names[4]
	local ranked = {
		{ max, lena }, { max, lena }, { lena, max }, { max, lena }, { jo, max }, { jo, max },
		{ max, jo }, { lena, jo }, { lena, jo }, { kim, lena }, { max, kim }, { max, kim },
	}
	local fun = { { lena, max }, { jo, kim }, { kim, jo }, { max, jo } }
	local data = {}
	local function of(name)
		data[name] = data[name] or { r = {}, h = {} }
		return data[name]
	end
	local function count(name, opponent, field)
		local h = of(name).h
		h[opponent] = h[opponent] or { w = 0, l = 0, rw = 0, rl = 0 }
		h[opponent][field] = h[opponent][field] + 1
	end
	for i, duel in ipairs(ranked) do
		local winner, loser = duel[1], duel[2]
		local id, t = "sample" .. i, now - (#ranked - i + 1) * 900
		table.insert(of(winner).r, { i = id, t = t, o = loser, w = true })
		table.insert(of(loser).r, { i = id, t = t, o = winner, w = false })
		count(winner, loser, "w")
		count(winner, loser, "rw")
		count(loser, winner, "l")
		count(loser, winner, "rl")
	end
	for _, duel in ipairs(fun) do
		count(duel[1], duel[2], "w")
		count(duel[2], duel[1], "l")
	end
	-- Both claim the win: disputed, left out of the ladder.
	table.insert(of(kim).r, { i = "sampledisputed", t = now - 300, o = max, w = true })
	table.insert(of(max).r, { i = "sampledisputed", t = now - 300, o = kim, w = true })
	return data
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Duels:Enable()
	ns.Comm:RegisterHandler(Stats, self.MSG, function(_, data, sender, meta)
		self:OnMessage(data, sender, meta)
	end)
	ns.Events:Register(Stats, "DUEL_REQUESTED", function(_, event, name)
		self:OnDuelRequested(event, name)
	end)
	ns.Events:Register(Stats, "DUEL_FINISHED", function()
		self:OnDuelFinished()
	end)
	-- Post-hooks only: they run after Blizzard's function, can't change or
	-- block it, and we never call these functions ourselves.
	Stats:PostHook("StartDuel", function(arg, _, toTheDeath)
		self:OnStartDuel(arg, toTheDeath == true)
	end)
	Stats:PostHook("AcceptDuel", function()
		self:OnAcceptDuel()
	end)
	Stats:PostHook("CancelDuel", function()
		self:OnCancelDuel()
	end)
	ns.TestMode:RegisterSim(Stats, { "duel" }, function(_, _, name, mode)
		self:Simulate(name, mode)
	end)
end
