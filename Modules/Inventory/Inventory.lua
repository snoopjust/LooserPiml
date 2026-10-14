-- Friends' inventory: what each LooserPiml friend carries in their bags and
-- keeps in their bank, plus their gold on hand, and everyone's wishlist.
--
-- Files:
--   Inventory.lua     this module: collecting (own character), sync, cache
--   Items.lua         item info (name, quality, icon, category) with async
--                     loading, and the search/filter/sort provider (pure)
--   Wishlist.lua      own wishlist, friends' wishlists, wishlist loot
--   InventoryTab.lua  the "Inventory" tab of the main window
--
-- Collecting (own character only, equipped items are never included):
--   bags  backpack, bags 1-4 and the reagent bag, rescanned SCAN_DELAY
--         seconds after the last BAG_UPDATE_DELAYED
--   bank  the bank can only be read while it is open: snapshot on
--         BANKFRAME_OPENED and after changes while it stays open; the last
--         snapshot is kept with its time
--   gold  GetMoney()
--
-- Sync (only to connected LooserPiml friends, see Core/Friends.lua):
--   INV full   the whole state; to a friend when their handshake arrives,
--              when they ask (INVREQ), and to everyone after a sharing
--              setting changed
--   INV delta  only what changed since the last message (absolute counts,
--              0 = gone), at most once per DELTA_INTERVAL seconds
--   INVREQ     "please send a full snapshot" (a delta didn't fit)
-- Every message carries the sender's session id and a sequence number; a
-- delta is only applied on top of exactly the state it was built from.
-- Not shared = not sent: a full snapshot without inventory (or gold) makes
-- receivers drop what they had cached for that friend.
--
-- Payloads (short keys, sanitized on receipt):
--   full  { f = true, s = sid, q = seq, a = at, i = { b = bags, k = bank, ka = bankAt } | nil, g = gold | nil }
--   delta { s = sid, q = seq, p = base seq, a = at, b = { [id] = count }, k = { [id] = count }, ka = bankAt, g = gold }
local _, ns = ...
local L = ns.L

local Inventory = ns:NewModule("Inventory")

Inventory.MSG = "INV"
Inventory.REQ_MSG = "INVREQ"
Inventory.SCAN_DELAY = 2        -- seconds after the last bag update before rescanning
Inventory.BANK_SCAN_DELAY = 0.5 -- the bank slots fill a moment after BANKFRAME_OPENED
Inventory.DELTA_INTERVAL = 30   -- seconds, minimum between two deltas
Inventory.FULL_DELAY = 3        -- seconds: collects several confirmed friends into one send
Inventory.REQ_COOLDOWN = 60     -- seconds between INVREQs to the same friend, and replies to them
Inventory.MAX_ITEMS = 600       -- distinct items per location accepted from a friend
Inventory.MAX_COUNT = 1000000   -- stack total accepted per item

-- Container indices on Forever (Enum.BagIndex in Blizzard's Forever UI code,
-- build 1.60.1). The account bank tabs are left out: they belong to the
-- whole account, not to this character. TODO(verify in-game): these
-- containers exist and are readable as listed.
local BagIndex = Enum and Enum.BagIndex or {}
local function idx(name, fallback)
	local value = BagIndex[name]
	return type(value) == "number" and value or fallback
end
Inventory.BAG_IDS = { idx("Backpack", 0), idx("Bag_1", 1), idx("Bag_2", 2), idx("Bag_3", 3), idx("Bag_4", 4), idx("ReagentBag", 5) }
Inventory.BANK_IDS = { idx("Characterbanktab", -2) }
for i = 1, 9 do
	Inventory.BANK_IDS[#Inventory.BANK_IDS + 1] = idx("CharacterBankTab_" .. i, 5 + i)
end

Inventory.defaults = {
	chars = {},   -- own characters: { bags, bank, bankAt, wishlist }
	friends = {}, -- fullName -> cached snapshot and wishlist of that friend
}

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------

function Inventory:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, self.defaults)
	self.fullSentTo = {} -- fullName -> true: has our current session's base state
	self.requested = {}  -- fullName -> GetTime() of our last INVREQ to them
	self.answered = {}   -- fullName -> GetTime() of our last full reply to their INVREQ
	self:RegisterOptions()
	if self.RegisterUI then
		self:RegisterUI()
	end
	if self.InitWishlist then
		self:InitWishlist()
	end
end

function Inventory:RegisterOptions()
	local Options = ns.Options
	Options:AddSection("inventory", L.OPT_SECTION_INVENTORY, 35)
	for _, entry in ipairs({
		{ "inventory", "inventory.share", L.OPT_SHARE_INVENTORY, L.OPT_SHARE_INVENTORY_TIP },
		{ "gold", "inventory.shareGold", L.OPT_SHARE_GOLD, L.OPT_SHARE_GOLD_TIP },
	}) do
		local kind = entry[1]
		Options:Add("inventory", {
			type = "checkbox", key = entry[2], label = entry[3], tooltip = entry[4], default = true,
			get = function()
				return ns.DB:IsShared(kind)
			end,
			set = function(value)
				ns.DB:SetShared(kind, value)
			end,
		})
	end
end

----------------------------------------------------------------------
-- Collecting
----------------------------------------------------------------------

function Inventory:GetChar()
	local name = ns.Roster:GetPlayerName() or "?"
	local char = self.db.chars[name]
	if not char then
		char = { bags = {}, bank = {} }
		self.db.chars[name] = char
	end
	char.bags = char.bags or {}
	char.bank = char.bank or {}
	char.wishlist = char.wishlist or {}
	return char
end

-- itemID -> total count over the given containers. Anything unreadable or
-- secret is skipped (that slot just doesn't count).
function Inventory.ReadContainers(ids)
	local counts = {}
	local api = C_Container
	if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then
		return counts
	end
	for _, bag in ipairs(ids) do
		local slots = api.GetContainerNumSlots(bag)
		if not ns.IsSecret(slots) and type(slots) == "number" then
			for slot = 1, slots do
				local info = api.GetContainerItemInfo(bag, slot)
				if type(info) == "table" and not ns.IsSecret(info) then
					local id, count = info.itemID, info.stackCount
					if not ns.IsSecret(id) and not ns.IsSecret(count) and type(id) == "number" and type(count) == "number" and count > 0 then
						counts[id] = (counts[id] or 0) + count
					end
				end
			end
		end
	end
	return counts
end

local function sameCounts(a, b)
	for id, n in pairs(a) do
		if b[id] ~= n then
			return false
		end
	end
	for id in pairs(b) do
		if a[id] == nil then
			return false
		end
	end
	return true
end

function Inventory:ScanBags()
	local char = self:GetChar()
	local bags = Inventory.ReadContainers(self.BAG_IDS)
	if not sameCounts(bags, char.bags) then
		char.bags = bags
		self:Changed()
	end
end

-- Only while the bank window is open; otherwise the bank containers read
-- as empty and would wipe the last snapshot.
function Inventory:ScanBank()
	if not self.bankOpen then
		return
	end
	local char = self:GetChar()
	local bank = Inventory.ReadContainers(self.BANK_IDS)
	char.bankAt = time()
	if not sameCounts(bank, char.bank) then
		char.bank = bank
	end
	self:Changed() -- bankAt changed in any case: friends see "bank now"
end

-- Debounced: bag events come in bursts (looting, sorting, crafting).
function Inventory:ScheduleScan()
	self.scanToken = (self.scanToken or 0) + 1
	local token = self.scanToken
	C_Timer.After(self.SCAN_DELAY, function()
		if token == self.scanToken then
			self:ScanBags()
			self:ScanBank()
		end
	end)
end

function Inventory:OnBankOpened()
	self.bankOpen = true
	C_Timer.After(self.BANK_SCAN_DELAY, function()
		self:ScanBank()
	end)
end

function Inventory:OnBankClosed()
	self:ScanBank() -- last look before it closes for good
	self.bankOpen = false
end

-- Gold on hand, or nil if not shared or unreadable.
function Inventory:GetSharedGold()
	if not ns.DB:IsShared("gold") or not GetMoney then
		return nil
	end
	local money = GetMoney()
	if ns.IsSecret(money) or type(money) ~= "number" or money < 0 then
		return nil
	end
	return math.floor(money)
end

function Inventory:Changed()
	ns.Events:Fire("LP_INVENTORY_CHANGED")
	self:RequestDelta()
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------

-- What I share right now: { bags, bank, bankAt, gold } (missing parts are
-- not shared).
function Inventory:CurrentState()
	local char = self:GetChar()
	local state = { gold = self:GetSharedGold() }
	if ns.DB:IsShared("inventory") then
		state.bags = ns.Util.DeepCopy(char.bags)
		state.bank = ns.Util.DeepCopy(char.bank)
		state.bankAt = char.bankAt
	end
	return state
end

local function fullPayload(self, state)
	local payload = { f = true, s = ns.Comm.session, q = self.seq or 0, a = GetServerTime(), g = state.gold }
	if state.bags then
		payload.i = { b = state.bags, k = state.bank, ka = state.bankAt }
	end
	return payload
end

-- counts changed between two maps: { [id] = new count (0 = gone) }, or nil
local function diffCounts(old, new)
	local diff, any = {}, false
	for id, n in pairs(new or {}) do
		if (old or {})[id] ~= n then
			diff[id], any = n, true
		end
	end
	for id in pairs(old or {}) do
		if not (new or {})[id] then
			diff[id], any = 0, true
		end
	end
	return any and diff or nil
end

-- Full snapshot to these friends (nil = every connected friend). It holds
-- the state of our last message, so the next delta still fits on top.
function Inventory:SendFull(names)
	if not self:IsEnabled() then
		return "off" -- a timer from before the module was disabled
	end
	if not self.base then
		self.base = self:CurrentState()
		self.seq = self.seq or 0
	end
	local result = ns.Comm:Send(self.MSG, fullPayload(self, self.base), { scope = "friends", to = names, prio = "BULK" })
	for _, name in ipairs(names or ns.Friends:GetConnected()) do
		self.fullSentTo[name] = true
	end
	return result
end

-- Full snapshot to friends whose handshake just arrived, collected for a
-- moment (several friends logging in at once get one send each anyway, but
-- not one per roster update).
function Inventory:QueueFull(name)
	self.fullQueue = self.fullQueue or {}
	self.fullQueue[#self.fullQueue + 1] = name
	if self.fullScheduled then
		return
	end
	self.fullScheduled = true
	C_Timer.After(self.FULL_DELAY, function()
		self.fullScheduled = false
		local names = self.fullQueue
		self.fullQueue = {}
		if #names > 0 then
			self:SendFull(names)
		end
	end)
end

-- A delta to friends who have our base state, at most every DELTA_INTERVAL.
function Inventory:RequestDelta()
	if not self:IsEnabled() then
		return "off"
	end
	if not self.base then
		return "no base" -- nobody has a snapshot yet; the next full one is current
	end
	local now = GetTime()
	local wait = self.lastDelta and (self.lastDelta + self.DELTA_INTERVAL - now) or 0
	if wait > 0.05 then
		if not self.deltaScheduled then
			self.deltaScheduled = true
			C_Timer.After(wait, function()
				self.deltaScheduled = false
				self:RequestDelta()
			end)
		end
		return "scheduled"
	end
	local state = self:CurrentState()
	local base = self.base
	-- A sharing switch changed what is shared at all: everyone gets a new
	-- full snapshot instead (a delta can't say "dropped").
	if (state.bags == nil) ~= (base.bags == nil) or (state.gold == nil) ~= (base.gold == nil) then
		return self:Resend()
	end
	local delta = {
		s = ns.Comm.session, p = self.seq, q = self.seq + 1, a = GetServerTime(),
		b = diffCounts(base.bags, state.bags),
		k = diffCounts(base.bank, state.bank),
	}
	if state.bankAt ~= base.bankAt then
		delta.ka = state.bankAt
	end
	if state.gold ~= base.gold then
		delta.g = state.gold
	end
	if not (delta.b or delta.k or delta.ka or delta.g) then
		return "unchanged"
	end
	local recipients = {}
	for name in pairs(self.fullSentTo) do
		if ns.Friends:IsConnected(name) then
			recipients[#recipients + 1] = name
		end
	end
	self.seq = self.seq + 1
	self.base = state
	self.lastDelta = now
	if #recipients == 0 then
		return "nobody"
	end
	table.sort(recipients)
	return ns.Comm:Send(self.MSG, delta, { scope = "friends", to = recipients, prio = "BULK" })
end

-- After a sharing switch: a fresh base and a full snapshot for everyone.
function Inventory:Resend()
	self.seq = (self.seq or 0) + 1
	self.base = self:CurrentState()
	self.fullSentTo = {}
	self.lastDelta = GetTime()
	return self:SendFull(nil)
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------

-- Untrusted counts map -> clean copy (item IDs and counts are whole
-- positive numbers, at most MAX_ITEMS entries), or nil.
function Inventory.CleanCounts(map, allowZero)
	if type(map) ~= "table" then
		return nil
	end
	local clean, n = {}, 0
	for id, count in pairs(map) do
		if type(id) == "number" and id == math.floor(id) and id > 0 and id < 10000000
			and type(count) == "number" and count == count and count >= (allowZero and 0 or 1) and count <= Inventory.MAX_COUNT then
			n = n + 1
			if n > Inventory.MAX_ITEMS then
				break
			end
			clean[id] = math.floor(count)
		end
	end
	return clean
end

local function cleanTime(t)
	return type(t) == "number" and t == t and t > 0 and t < 4e9 and math.floor(t) or nil
end

local function cleanGold(g)
	return type(g) == "number" and g == g and g >= 0 and g <= 1e13 and math.floor(g) or nil
end

local function applyDiff(map, diff)
	for id, n in pairs(diff or {}) do
		map[id] = n > 0 and n or nil
	end
end

function Inventory:OnInventoryMessage(data, sender, meta)
	if meta.test or type(data) ~= "table" then
		return
	end
	local cache = self.db.friends[sender] or {}
	if data.f then
		cache.sid, cache.seq = data.s, tonumber(data.q) or 0
		cache.at = cleanTime(data.a)
		cache.gold = cleanGold(data.g)
		local inv = type(data.i) == "table" and data.i or nil
		cache.bags = inv and (Inventory.CleanCounts(inv.b) or {}) or nil
		cache.bank = inv and (Inventory.CleanCounts(inv.k) or {}) or nil
		cache.bankAt = inv and cleanTime(inv.ka) or nil
	elseif cache.sid ~= nil and cache.sid == data.s and cache.seq == data.p then
		cache.seq = tonumber(data.q) or cache.seq
		cache.at = cleanTime(data.a) or cache.at
		if cache.bags then
			applyDiff(cache.bags, Inventory.CleanCounts(data.b, true))
			applyDiff(cache.bank, Inventory.CleanCounts(data.k, true))
			cache.bankAt = cleanTime(data.ka) or cache.bankAt
		end
		if data.g ~= nil then
			cache.gold = cleanGold(data.g)
		end
	else
		-- A delta for a state we don't have (missed message, new session):
		-- ask for the whole thing, but not more than once a minute.
		self:RequestFull(sender)
		return
	end
	cache.seen = time()
	self.db.friends[sender] = cache
	ns.Events:Fire("LP_INVENTORY_CHANGED", sender)
end

function Inventory:RequestFull(name)
	local now = GetTime()
	local last = self.requested[name]
	if last and now - last < self.REQ_COOLDOWN then
		return
	end
	self.requested[name] = now
	ns.Comm:Send(self.REQ_MSG, {}, { scope = "friends", to = { name } })
end

function Inventory:OnFullRequest(_, sender, meta)
	if meta.test then
		return
	end
	local now = GetTime()
	local last = self.answered[sender]
	if last and now - last < self.REQ_COOLDOWN then
		return
	end
	self.answered[sender] = now
	self:SendFull({ sender })
end

----------------------------------------------------------------------
-- Cached data for the UI
----------------------------------------------------------------------

-- Everyone whose inventory or gold we may show: me plus listed friends who
-- answered a handshake. { name, class, isSelf, online, seen, bags, bank,
-- bankAt, gold, wishlist }. bags/bank nil = not shared.
function Inventory:GetHolders()
	local char = self:GetChar()
	local shareInv = ns.DB:IsShared("inventory")
	local list = {
		{
			name = ns.Roster:GetPlayerName(), class = ns.Roster:GetPlayerClass(), isSelf = true, online = true,
			seen = time(), bags = shareInv and char.bags or nil, bank = shareInv and char.bank or nil,
			bankAt = char.bankAt, gold = self:GetSharedGold(), wishlist = char.wishlist,
		},
	}
	for name, entry in pairs(ns.Friends:GetDB()) do
		if entry.handshake and not ns.Roster:IsPlayer(name) then
			local cache = self.db.friends[name] or {}
			list[#list + 1] = {
				name = name, class = entry.class, online = ns.Friends:IsOnline(name), seen = cache.seen or entry.lastSeen,
				bags = cache.bags, bank = cache.bank, bankAt = cache.bankAt, gold = cache.gold, wishlist = cache.wishlist,
			}
		end
	end
	if ns.TestMode:IsEnabled() and self.sampleHolders then
		for _, holder in ipairs(self.sampleHolders) do
			list[#list + 1] = holder
		end
	end
	return list
end

----------------------------------------------------------------------
-- Test mode: sample friends' bags (never saved, never sent)
----------------------------------------------------------------------

Inventory.SAMPLE = {
	{ name = "Max", class = "WARRIOR", gold = 716000, bags = { [2589] = 40, [2318] = 12, [118] = 5 }, bank = { [2589] = 60, [2319] = 54 }, bankAgo = 3 * 86400 },
	{ name = "Lena", class = "MAGE", gold = 1250000, bags = { [4306] = 20, [118] = 2 }, bank = {}, bankAgo = 3600, wishlist = { { id = 2319, n = 60 } } },
	{ name = "Jo", class = "PRIEST", gold = 98000, bags = { [2140] = 1, [2589] = 8 }, bank = { [2318] = 30 }, wishlist = { { id = 2589, n = 200 } } },
	{ name = "Kim", class = "ROGUE", bags = { [2319] = 6 }, bank = { [2319] = 14 }, bankAgo = 86400 },
}

function Inventory:FillSamples()
	if not ns.TestMode:IsEnabled() then
		return
	end
	local now = time()
	self.sampleHolders = {}
	for i, sample in ipairs(self.SAMPLE) do
		self.sampleHolders[i] = {
			name = ns.Roster:Normalize(sample.name), class = sample.class, online = i ~= 4, fake = true,
			seen = i == 4 and now - 20 * 3600 or now, bags = ns.Util.DeepCopy(sample.bags), bank = ns.Util.DeepCopy(sample.bank),
			bankAt = sample.bankAgo and now - sample.bankAgo or nil, gold = sample.gold,
			wishlist = sample.wishlist,
		}
	end
	ns.Events:Fire("LP_INVENTORY_CHANGED")
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function Inventory:OnEnable()
	ns.Comm:RegisterHandler(self, self.MSG, self.OnInventoryMessage)
	ns.Comm:RegisterHandler(self, self.REQ_MSG, self.OnFullRequest)
	ns.Events:Register(self, "BAG_UPDATE_DELAYED", "ScheduleScan")
	-- The main bank container fires this instead of BAG_UPDATE.
	ns.Events:Register(self, "PLAYERBANKSLOTS_CHANGED", "ScheduleScan")
	ns.Events:Register(self, "BANKFRAME_OPENED", "OnBankOpened")
	ns.Events:Register(self, "BANKFRAME_CLOSED", "OnBankClosed")
	ns.Events:Register(self, "PLAYER_MONEY", "RequestDelta")
	ns.Events:Register(self, "LP_FRIEND_CONFIRMED", function(_, _, name)
		self:QueueFull(name)
		if self.QueueWishlist then
			self:QueueWishlist(name)
		end
	end)
	ns.Events:Register(self, "LP_SHARING_CHANGED", function(_, _, kind)
		if kind == "gold" or kind == "inventory" then
			self:Resend()
		end
	end)
	ns.Events:Register(self, "LP_FILL_SAMPLES", "FillSamples")
	if self.EnableWishlist then
		self:EnableWishlist()
	end
	self:ScanBags()
end
