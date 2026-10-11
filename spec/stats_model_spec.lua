local H = require("helpers")

-- Local timestamp helper: the model works in local time like the game.
local function at(y, m, d, hour, min)
	return os.time({ year = y, month = m, day = d, hour = hour or 12, min = min or 0, sec = 0 })
end

local function ev(t, type, data, extra)
	local e = { t = t, type = type, data = data or {} }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return e
end

describe("Stats model", function()
	after_each(H.checkClients)

	local Model

	before_each(function()
		local _, ns = H.client()
		Model = ns:GetModule("Stats").Model
	end)

	describe("periods", function()
		it("starts a gaming day at 06:00, so after midnight still counts as tonight", function()
			assert.are.equal("2026-10-10", Model.DayKey(at(2026, 10, 11, 1, 30)))
			assert.are.equal("2026-10-10", Model.DayKey(at(2026, 10, 11, 5, 59)))
			assert.are.equal("2026-10-11", Model.DayKey(at(2026, 10, 11, 6, 0)))
			assert.are.equal(at(2026, 10, 10, 6, 0), Model.DayStart(at(2026, 10, 11, 2, 0)))
		end)

		it("starts the week on Monday 06:00", function()
			-- 2026-10-14 is a Wednesday, 2026-10-12 a Monday
			assert.are.equal(at(2026, 10, 12, 6, 0), Model.WeekStart(at(2026, 10, 14, 20, 0)))
			-- Monday 05:00 still belongs to the previous gaming week
			assert.are.equal(at(2026, 10, 5, 6, 0), Model.WeekStart(at(2026, 10, 12, 5, 0)))
			assert.are.equal("2026-10-12", Model.WeekKey(at(2026, 10, 18, 23, 0)))
			assert.is_nil(Model.PeriodStart("all", at(2026, 10, 14)))
		end)
	end)

	describe("events", function()
		it("counts every event type into the aggregate", function()
			local t = at(2026, 10, 11, 20)
			local agg = Model.Empty()
			Model.AddEvent(agg, ev(t, "death", { drowned = true, duringEncounter = true }, { inInstance = true }))
			Model.AddEvent(agg, ev(t, "level_up", { level = 12, played = 1800, complete = true }))
			Model.AddEvent(agg, ev(t, "level_up", { level = 13, played = 900, complete = false }))
			Model.AddEvent(agg, ev(t, "quest_done", { xp = 450, money = 1200 }))
			Model.AddEvent(agg, ev(t, "money", { delta = 5000, source = "loot" }))
			Model.AddEvent(agg, ev(t, "money", { delta = -300, source = "repair" }))
			Model.AddEvent(agg, ev(t, "loot_rare", { quality = 4 }))
			Model.AddEvent(agg, ev(t, "instance", { action = "enter", itype = "party" }))
			Model.AddEvent(agg, ev(t, "instance", { action = "leave", itype = "party" }))
			Model.AddEvent(agg, ev(t, "encounter", { success = true }))
			Model.AddEvent(agg, ev(t, "encounter", { success = false }))
			Model.AddEvent(agg, ev(t, "profession", { kind = "skillup", profession = true }))
			Model.AddEvent(agg, ev(t, "profession", { kind = "crafted", count = 3 }))
			Model.AddEvent(agg, ev(t, "travel", { kind = "flight" }))
			Model.AddEvent(agg, ev(t, "duel", { result = "opponent_fled" }))
			Model.AddEvent(agg, ev(t, "duel", { result = "fled" }))
			Model.AddEvent(agg, ev(t, "pvp", { kind = "finished", won = true, killingBlows = 4 }))
			Model.AddEvent(agg, ev(t, "something_from_the_future", { x = 1 }))

			local n = agg.n
			assert.are.equal(1, n.deaths)
			assert.are.equal(1, n.drowned)
			assert.are.equal(1, n.deathsInInstance)
			assert.are.equal(1, n.deathsInEncounter)
			assert.are.equal(2, n.levelUps)
			assert.are.equal(13, agg.maxLevel)
			assert.are.equal(1800, n.levelTime) -- the incomplete level doesn't count
			assert.are.equal(1, n.levelTimeCount)
			assert.are.equal(1, n.quests)
			assert.are.equal(450, n.questXP)
			assert.are.equal(5000, n.moneyLooted)
			assert.are.equal(5000, agg.moneyIn.loot)
			assert.are.equal(300, agg.moneyOut.repair)
			assert.are.equal(1, n.lootEpic)
			assert.are.equal(1, n.dungeons)
			assert.are.equal(1, n.instancesEntered)
			assert.are.equal(1, n.bossKills)
			assert.are.equal(1, n.bossWipes)
			assert.are.equal(1, n.professionSkillUps)
			assert.are.equal(3, n.crafted)
			assert.are.equal(1, n.flights)
			assert.are.equal(1, n.duelsWon)
			assert.are.equal(1, n.duelsLost)
			assert.are.equal(1, n.duelsFled)
			assert.are.equal(1, n.bgWon)
			assert.are.equal(4, n.bgKillingBlows)
			assert.are.equal(t, agg.at.deaths)
			assert.are.equal(1800, Model.AverageLevelTime(agg))
		end)

		it("merges aggregates: sums counters, keeps the latest time and snapshot", function()
			local a, b = Model.Empty(), Model.Empty()
			Model.Add(a, "deaths", 2, 100)
			Model.Add(b, "deaths", 3, 50)
			a.moneyIn.loot = 10
			b.moneyIn.loot = 5
			Model.AddEvent(a, ev(100, "pvp", { kind = "honor", honor = 10 }))
			Model.AddEvent(b, ev(200, "pvp", { kind = "honor", honor = 25 }))
			b.maxLevel = 20
			Model.Merge(a, b)
			assert.are.equal(5, a.n.deaths)
			assert.are.equal(100, a.at.deaths)
			assert.are.equal(15, a.moneyIn.loot)
			assert.are.equal(25, a.last.honor.v)
			assert.are.equal(20, a.maxLevel)
		end)
	end)

	describe("rollup and cap", function()
		local function totals(log, buckets)
			local agg = Model.Aggregate(log, buckets, nil)
			return agg.n.deaths or 0, agg.n.moneyLooted or 0
		end

		it("rolls events older than 30 days into daily buckets without changing totals", function()
			local now = at(2026, 10, 11, 20)
			local log, buckets = {}, {}
			for i = 40, 1, -1 do -- one death + loot per day, oldest first
				local t = now - i * 86400
				log[#log + 1] = ev(t, "death")
				log[#log + 1] = ev(t, "money", { delta = 100, source = "loot" })
			end
			local deathsBefore, lootBefore = totals(log, buckets)
			local rolled = Model.Compact(log, buckets, now)
			assert.is_true(rolled > 0)
			for _, e in ipairs(log) do
				assert.is_true(e.t >= now - 30 * 86400)
			end
			assert.is_not_nil(buckets[Model.DayKey(now - 40 * 86400)])
			local deathsAfter, lootAfter = totals(log, buckets)
			assert.are.equal(deathsBefore, deathsAfter)
			assert.are.equal(lootBefore, lootAfter)
		end)

		it("caps the log at N events, oldest first", function()
			local now = at(2026, 10, 11, 20)
			local log, buckets = {}, {}
			for i = 1, 25 do
				log[i] = ev(now - (26 - i) * 60, "death")
			end
			Model.Compact(log, buckets, now, 10, 30)
			assert.are.equal(10, #log)
			assert.are.equal(now - 10 * 60, log[1].t) -- the 10 newest stay
			assert.are.equal(25, Model.Aggregate(log, buckets, nil).n.deaths)
		end)
	end)

	describe("aggregation per period", function()
		it("uses log events and buckets, separated into tonight, this week and all time", function()
			local now = at(2026, 10, 14, 22) -- Wednesday evening
			local log = {
				ev(at(2026, 10, 14, 19), "death"),         -- tonight
				ev(at(2026, 10, 15, 1), "death"),           -- after midnight: still tonight (in the future here, fine)
				ev(at(2026, 10, 13, 21), "death"),          -- Tuesday: this week
				ev(at(2026, 10, 11, 21), "death"),          -- last Sunday: all time only
			}
			local buckets = {}
			Model.Add(Model.Bucket(buckets, at(2026, 10, 14, 18)), "jumps", 7, at(2026, 10, 14, 18))
			Model.Add(Model.Bucket(buckets, at(2026, 10, 1, 18)), "jumps", 3, at(2026, 10, 1, 18))

			local all = Model.AggregateAll(log, buckets, now)
			assert.are.equal(2, all.tonight.n.deaths)
			assert.are.equal(3, all.week.n.deaths)
			assert.are.equal(4, all.all.n.deaths)
			assert.are.equal(7, all.tonight.n.jumps)
			assert.are.equal(7, all.week.n.jumps)
			assert.are.equal(10, all.all.n.jumps)
		end)
	end)

	describe("sanitizing received aggregates", function()
		it("keeps well-formed values and drops everything else", function()
			local clean = Model.Sanitize({
				n = { deaths = 3, bad = -1, nan = 0 / 0, huge = 1e30, text = "5", [7] = 1 },
				moneyIn = { loot = 100, ["|cffff0000evil"] = 5 },
				at = { deaths = 1760000000 },
				last = { honor = { v = 10, t = 5 }, broken = { v = "x", t = 1 } },
				maxLevel = 25,
				extra = { whatever = true },
			})
			assert.are.same({ deaths = 3 }, clean.n)
			assert.are.equal(100, clean.moneyIn.loot)
			assert.are.equal(5, clean.moneyIn["cffff0000evil"])
			assert.are.equal(10, clean.last.honor.v)
			assert.is_nil(clean.last.broken)
			assert.are.equal(25, clean.maxLevel)
			assert.is_nil(clean.extra)
			assert.are.same(Model.Empty(), Model.Sanitize("garbage"))
		end)
	end)
end)
