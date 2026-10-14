-- Timeline: what happened to you and your LooserPiml friends, newest last.
--
-- The Ticker adds every own event and every ticker event received from a
-- friend (never simulated ones). Entries are kept locally for MAX_AGE (7
-- days), so the Tonight tab and the evening recap survive /reload and a
-- restart. Nothing here is sent anywhere.
--
-- Entry: { t = server time, s = sender "Name-Realm", k = kind ("death",
--          "levelup", "enter", "leave", "wishloot"), x = display text,
--          v = icon variant, id = item ID, n = count }
local _, ns = ...

local Timeline = {}
ns:RegisterCore("Timeline", Timeline)

Timeline.MAX_AGE = 7 * 86400
Timeline.MAX_ENTRIES = 1000

function Timeline:GetDB()
	return ns.DB:Get("timeline")
end

function Timeline:Prune(now)
	local list = self:GetDB()
	local cutoff = (now or time()) - self.MAX_AGE
	local keep = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" and type(entry.t) == "number" and entry.t >= cutoff then
			keep[#keep + 1] = entry
		end
	end
	while #keep > self.MAX_ENTRIES do
		table.remove(keep, 1)
	end
	ns.DB:Set("timeline", keep)
end

function Timeline:Add(entry)
	local list = self:GetDB()
	entry.t = entry.t or GetServerTime()
	list[#list + 1] = entry
	if #list > self.MAX_ENTRIES then
		self:Prune(entry.t)
	end
	ns.Events:Fire("LP_TIMELINE_CHANGED")
end

-- Entries from `from` (inclusive) up to `to` (exclusive, default: now),
-- oldest first.
function Timeline:Between(from, to)
	local out = {}
	for _, entry in ipairs(self:GetDB()) do
		if entry.t >= from and (not to or entry.t < to) then
			out[#out + 1] = entry
		end
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

function Timeline:OnEnable()
	self:Prune()
end
