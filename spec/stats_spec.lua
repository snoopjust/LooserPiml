local H = require("helpers")

describe("Ticker stats", function()
	after_each(H.checkClients)

	local mock, ns, Stats

	before_each(function()
		mock, ns = H.client()
		Stats = ns:GetModule("Ticker").Stats
	end)

	it("counts deaths, drownings and level-ups per player", function()
		Stats:Record("Max-TestRealm", { k = "death", c = "WARRIOR" })
		Stats:Record("Max-TestRealm", { k = "death", dr = true })
		Stats:Record("Lena-TestRealm", { k = "levelup", lvl = 12, c = "MAGE" })

		local max = Stats:Get("Max-TestRealm", "session")
		assert.are.equal(2, max.deaths)
		assert.are.equal(1, max.drowned)
		assert.are.equal("WARRIOR", max.class)
		assert.are.equal(2, Stats:Get("Max-TestRealm", "alltime").deaths)
		assert.are.equal(12, Stats:Get("Lena-TestRealm", "alltime").level)
		assert.are.equal(1, Stats:Get("Lena-TestRealm", "session").levelUps)
	end)

	it("keeps test events out of the all-time stats", function()
		Stats:Record("Max-TestRealm", { k = "death" }, true)
		assert.are.equal(1, Stats:Get("Max-TestRealm", "session").deaths)
		assert.is_nil(Stats:Get("Max-TestRealm", "alltime"))
	end)

	it("ranks by count, then name", function()
		Stats:Record("Kim-TestRealm", { k = "death" })
		Stats:Record("Max-TestRealm", { k = "death" })
		Stats:Record("Max-TestRealm", { k = "death" })
		Stats:Record("Jo-TestRealm", { k = "death" })
		local ranking = Stats:Ranking("deaths", "session")
		assert.are.equal("Max-TestRealm", ranking[1].name)
		assert.are.equal("Jo-TestRealm", ranking[2].name)
		assert.are.equal("Kim-TestRealm", ranking[3].name)
	end)

	it("/lp stats crowns the Death King", function()
		for _ = 1, 3 do
			Stats:Record("Max-TestRealm", { k = "death", c = "WARRIOR" })
		end
		Stats:Record("Lena-TestRealm", { k = "death", c = "MAGE" })
		ns.Slash:Dispatch("stats chat")
		local plain = {}
		for i, line in ipairs(mock.chat) do
			plain[i] = H.stripColors(line)
		end
		local text = table.concat(plain, "\n")
		assert.matches("Death King: Max %(3%)", text)
		assert.matches("Deaths this session: Max %(3%), Lena %(1%)", text)
	end)

	it("says so when nobody died", function()
		ns.Slash:Dispatch("stats chat")
		assert.is_true(mock:ChatContains("Nobody died this session"))
	end)

	it("persists all-time stats across a reload, but not session stats", function()
		Stats:Record("Max-TestRealm", { k = "death" })
		local saved = mock.env.LooserPimlDB
		local _, ns2 = H.client({ savedVariables = saved })
		local Stats2 = ns2:GetModule("Ticker").Stats
		assert.are.equal(1, Stats2:Get("Max-TestRealm", "alltime").deaths)
		assert.is_nil(Stats2:Get("Max-TestRealm", "session"))
	end)
end)
