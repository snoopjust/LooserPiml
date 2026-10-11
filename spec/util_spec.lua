local H = require("helpers")

describe("Util", function()
	after_each(H.checkClients)

	local Util

	before_each(function()
		local _, ns = H.client()
		Util = ns.Util
	end)

	describe("MatchFormat (localized GlobalStrings)", function()
		it("matches simple %s and %d formats", function()
			local args = Util.MatchFormat("You receive loot: [Linen Cloth].", "You receive loot: %s.")
			assert.are.same({ "[Linen Cloth]" }, args)
			args = Util.MatchFormat("You receive loot: [Linen Cloth]x5.", "You receive loot: %sx%d.")
			assert.are.equal("[Linen Cloth]", args[1])
			assert.are.equal(5, Util.ToNumber(args[2]))
			args = Util.MatchFormat("Your skill in Defense has increased to 14.", "Your skill in %s has increased to %d.")
			assert.are.same({ "Defense", "14" }, args)
		end)

		it("returns positional arguments in argument order, not text order", function()
			local knockout = "%1$s has defeated %2$s in a duel"
			local retreat = "%2$s has fled from %1$s in a duel"
			assert.are.same({ "Max", "Norber" }, Util.MatchFormat("Max has defeated Norber in a duel", knockout))
			-- winner is %1$s even though the loser comes first in the sentence
			assert.are.same({ "Max", "Norber" }, Util.MatchFormat("Norber has fled from Max in a duel", retreat))
		end)

		it("escapes pattern characters and handles %% and German formats", function()
			assert.are.same({ "50" }, Util.MatchFormat("Discount (50%)", "Discount (%d%%)"))
			assert.are.same({ "[Leinenstoff]" }, Util.MatchFormat("Ihr erhaltet Beute: [Leinenstoff].", "Ihr erhaltet Beute: %s."))
			assert.is_nil(Util.MatchFormat("You receive loot: X", "You receive loot: %s."))
			assert.is_nil(Util.MatchFormat("anything", nil))
			assert.is_nil(Util.MatchFormat(nil, "%s"))
		end)

		it("never touches secret text", function()
			assert.is_nil(Util.MatchFormat(H.Mock.Secret(), "%s"))
		end)
	end)

	describe("formatting", function()
		it("formats money as gold, silver and copper", function()
			assert.are.equal("12g 34s 56c", Util.FormatMoney(123456))
			assert.are.equal("1g", Util.FormatMoney(10000))
			assert.are.equal("5s 1c", Util.FormatMoney(501))
			assert.are.equal("0c", Util.FormatMoney(0))
			assert.are.equal("-2s", Util.FormatMoney(-200))
		end)

		it("formats durations", function()
			assert.are.equal("42s", Util.FormatDuration(42))
			assert.are.equal("5m", Util.FormatDuration(300))
			assert.are.equal("1h 23m", Util.FormatDuration(5025))
		end)
	end)
end)
