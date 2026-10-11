-- Every gold change of the own character, with a coarse source.
--
-- PLAYER_MONEY carries no payload and no reason, so the source is inferred
-- from context:
--   1. a short-lived hint from something we just saw happen (quest turned in,
--      repair, flight taken, mail money taken - AH sale or normal mail)
--   2. otherwise which interaction window is open (loot, merchant, mail,
--      trade, auction house, trainer, flight map)
--   3. otherwise "other"
-- The money update can arrive a moment after the window closed, so windows
-- count as open for WINDOW_GRACE seconds after closing.
local _, ns = ...

local Stats = ns:GetModule("Stats")

Stats.MONEY_HINT_TTL = 5 -- seconds a hint stays valid
Stats.WINDOW_GRACE = 2   -- seconds a window counts as open after closing

Stats.MONEY_SOURCES = {
	"loot", "quest", "vendor_sell", "vendor_buy", "repair", "ah_mail",
	"auction", "trainer", "flight", "trade", "mail", "other",
}

-- window name -> { open event, close event }
Stats.MONEY_WINDOWS = {
	loot = { "LOOT_OPENED", "LOOT_CLOSED" },
	merchant = { "MERCHANT_SHOW", "MERCHANT_CLOSED" },
	mail = { "MAIL_SHOW", "MAIL_CLOSED" },
	trade = { "TRADE_SHOW", "TRADE_CLOSED" },
	auction = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
	trainer = { "TRAINER_SHOW", "TRAINER_CLOSED" },
	taxi = { "TAXIMAP_OPENED", "TAXIMAP_CLOSED" },
}

-- Pure: source for a money delta given the active hint and the set of
-- (recently) open windows. Order matters: the most specific signal wins.
function Stats.ClassifyMoney(delta, hint, windows)
	if hint then
		return hint
	end
	windows = windows or {}
	if windows.loot then
		return "loot"
	elseif windows.merchant then
		return delta > 0 and "vendor_sell" or "vendor_buy"
	elseif windows.trade then
		return "trade"
	elseif windows.mail then
		return "mail"
	elseif windows.auction then
		return "auction"
	elseif windows.trainer then
		return "trainer"
	elseif windows.taxi then
		return "flight"
	end
	return "other"
end

function Stats:SetMoneyHint(source)
	self.moneyHint = { source = source, at = GetTime() }
end

function Stats:TakeMoneyHint()
	local hint = self.moneyHint
	self.moneyHint = nil
	if hint and GetTime() - hint.at <= self.MONEY_HINT_TTL then
		return hint.source
	end
	return nil
end

function Stats:ActiveWindows()
	local now, active = GetTime(), {}
	for name, state in pairs(self.windows or {}) do
		if state.open or (state.closedAt and now - state.closedAt <= self.WINDOW_GRACE) then
			active[name] = true
		end
	end
	return active
end

local function readMoney()
	local money = GetMoney and GetMoney()
	if ns.IsSecret(money) or type(money) ~= "number" then
		return nil
	end
	return money
end

function Stats:OnPlayerMoney()
	local money = readMoney()
	if not money then
		return
	end
	local previous = self.lastMoney
	self.lastMoney = money
	if not previous or money == previous then
		return
	end
	local delta = money - previous
	local source = Stats.ClassifyMoney(delta, self:TakeMoneyHint(), self:ActiveWindows())
	self:Record("money", { delta = delta, source = source })
end

function Stats:EnableMoney()
	self.windows = {}
	self.lastMoney = readMoney()
	ns.Events:Register(self, "PLAYER_MONEY", "OnPlayerMoney")
	for name, events in pairs(self.MONEY_WINDOWS) do
		-- Close first: without a close event a window would stay "open"
		-- forever and mislabel all later gold, so then we skip it entirely.
		local hasClose = ns.Events:Register(self, events[2], function()
			self.windows[name] = { open = false, closedAt = GetTime() }
		end)
		if hasClose then
			ns.Events:Register(self, events[1], function(_, _, ...)
				self.windows[name] = { open = true }
				if name == "loot" and self.OnLootOpened then
					self:OnLootOpened(...) -- Loot.lua: gathering detection
				end
			end)
		end
	end
	-- RepairAllItems(useGuildBank): "repair all" at a vendor.
	self:PostHook("RepairAllItems", function(useGuildBank)
		if not useGuildBank then
			self:SetMoneyHint("repair")
		end
	end)
	-- Taking money from a mail: an auction house sale has a "seller" invoice.
	-- TODO(verify in-game): the mail is still readable in the post-hook.
	local function onMailMoney(index)
		local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
		if ns.IsSecret(invoiceType) then
			invoiceType = nil
		end
		self:SetMoneyHint(invoiceType == "seller" and "ah_mail" or "mail")
	end
	self:PostHook("TakeInboxMoney", onMailMoney)
	self:PostHook("AutoLootMailItem", onMailMoney)
end
