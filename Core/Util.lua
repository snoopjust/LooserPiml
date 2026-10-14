-- Small pure helpers shared by core services and modules. No game API calls
-- in here except where noted, so everything is testable offline.
local _, ns = ...

local Util = {}
ns.Util = Util

----------------------------------------------------------------------
-- Localized system messages
----------------------------------------------------------------------
-- The client builds messages like "You receive loot: [Item]." from format
-- strings in its GlobalStrings (LOOT_ITEM_SELF = "You receive loot: %s.").
-- Those strings are localized, so matching hard-coded English would break
-- on a German client. Instead we turn the client's own format string into a
-- Lua pattern. Formats may use positional arguments ("%2$s has fled from
-- %1$s"), so captures are returned in argument order, not text order.

local patternCache = {}

-- Returns pattern, argIndexForCapture (array) or nil for a non-string.
function Util.FormatToPattern(fmt)
	if type(fmt) ~= "string" then
		return nil
	end
	local cached = patternCache[fmt]
	if cached then
		return cached.pattern, cached.order
	end
	local out, order = { "^" }, {}
	local nextArg = 1
	local i, n = 1, #fmt
	while i <= n do
		local c = fmt:sub(i, i)
		if c == "%" then
			-- %s, %d, %1$s, %2$d, %.1f, %% ...
			local whole, posPart, conv = fmt:match("^(%%(%d*%$?)[%-%.%d]*([sdfgi%%]))", i)
			if not whole then
				out[#out + 1] = "%%" -- stray percent: match literally
				i = i + 1
			elseif conv == "%" then
				out[#out + 1] = "%%"
				i = i + #whole
			else
				local argIndex = tonumber(posPart:match("^(%d+)%$$") or "")
				if not argIndex then
					argIndex = nextArg
					nextArg = nextArg + 1
				end
				order[#order + 1] = argIndex
				if conv == "s" then
					out[#out + 1] = "(.-)"
				else
					out[#out + 1] = "(%-?[%d%.,]+)"
				end
				i = i + #whole
			end
		else
			if c:match("[%^%$%(%)%.%[%]%*%+%-%?]") then
				out[#out + 1] = "%" .. c
			else
				out[#out + 1] = c
			end
			i = i + 1
		end
	end
	out[#out + 1] = "$"
	local pattern = table.concat(out)
	patternCache[fmt] = { pattern = pattern, order = order }
	return pattern, order
end

-- Matches text against a client format string. Returns the arguments in
-- argument order (args[1] is what the client put into %1$s / the first %s),
-- or nil if it doesn't match. Numeric conversions come back as numbers.
function Util.MatchFormat(text, fmt)
	if type(text) ~= "string" or ns.IsSecret(text) then
		return nil
	end
	local pattern, order = Util.FormatToPattern(fmt)
	if not pattern then
		return nil
	end
	local captures = { text:match(pattern) }
	if #captures == 0 or #captures ~= #order then
		return nil
	end
	local args = {}
	for capture, argIndex in ipairs(order) do
		local value = captures[capture]
		args[argIndex] = value
	end
	return args
end

-- Number from a captured %d (clients may use digit separators).
function Util.ToNumber(text)
	if type(text) == "number" then
		return text
	end
	if type(text) ~= "string" then
		return nil
	end
	return tonumber((text:gsub(",", "")))
end

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------

-- 123456 -> "12g 34s 56c"; zero parts are left out; 0 -> "0c".
function Util.FormatMoney(copper)
	copper = math.floor(tonumber(copper) or 0)
	local negative = copper < 0
	copper = math.abs(copper)
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local rest = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = gold .. "g"
	end
	if silver > 0 then
		parts[#parts + 1] = silver .. "s"
	end
	if rest > 0 or #parts == 0 then
		parts[#parts + 1] = rest .. "c"
	end
	return (negative and "-" or "") .. table.concat(parts, " ")
end

-- 5025 -> "1h 23m", 300 -> "5m", 42 -> "42s".
function Util.FormatDuration(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	if seconds < 60 then
		return seconds .. "s"
	end
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return minutes .. "m"
end

----------------------------------------------------------------------
-- Tables
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Own loot messages and item links
----------------------------------------------------------------------

-- Own-loot GlobalStrings, "...MULTIPLE" first: the single form would also
-- match "[Item]x2." and swallow the count.
Util.LOOT_FORMATS = {
	{ name = "LOOT_ITEM_SELF_MULTIPLE", kind = "loot", multiple = true },
	{ name = "LOOT_ITEM_SELF", kind = "loot" },
	{ name = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", kind = "loot", multiple = true },
	{ name = "LOOT_ITEM_PUSHED_SELF", kind = "loot" },
	{ name = "LOOT_ITEM_CREATED_SELF_MULTIPLE", kind = "created", multiple = true },
	{ name = "LOOT_ITEM_CREATED_SELF", kind = "created" },
}

-- Classic item link colors, used only if the item API can't tell yet.
local LINK_COLORS = {
	ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6,
}

-- Quality of an item link: the item API first (nil while the item isn't
-- cached yet), then the quality marker or color embedded in the link.
function Util.ItemQuality(link)
	if type(link) ~= "string" then
		return nil
	end
	local getQuality = C_Item and C_Item.GetItemQualityByID
	if getQuality then
		local quality = getQuality(link)
		if type(quality) == "number" and not ns.IsSecret(quality) then
			return quality
		end
	end
	local marker = link:match("|cnIQ(%d+):")
	if marker then
		return tonumber(marker)
	end
	local color = link:match("|c(%x%x%x%x%x%x%x%x)")
	return color and LINK_COLORS[color:lower()] or nil
end

-- Parses an own loot/create message. Returns kind, link, count or nil.
function Util.ParseOwnLoot(text)
	for _, format in ipairs(Util.LOOT_FORMATS) do
		local fmt = _G[format.name]
		local args = fmt and Util.MatchFormat(text, fmt)
		if args then
			local count = format.multiple and Util.ToNumber(args[2]) or 1
			return format.kind, args[1], count
		end
	end
	return nil
end

-- Item ID from an item link ("|Hitem:2589:..."), or nil.
function Util.ItemIDFromLink(link)
	if type(link) ~= "string" or ns.IsSecret(link) then
		return nil
	end
	return tonumber(link:match("|Hitem:(%d+)"))
end

-- "now", "12 min ago", "3 h ago", "yesterday", "4 days ago" for a time in
-- the past (server time). nil -> nil.
function Util.FormatAgo(t, now)
	if type(t) ~= "number" then
		return nil
	end
	local L = ns.L
	local seconds = (now or time()) - t
	if seconds < 120 then
		return L.AGO_NOW
	elseif seconds < 3600 then
		return L.AGO_MINUTES:format(math.floor(seconds / 60))
	elseif seconds < 20 * 3600 then
		return L.AGO_HOURS:format(math.floor(seconds / 3600))
	end
	local days = math.floor((seconds + 4 * 3600) / 86400)
	if days <= 1 then
		return L.AGO_YESTERDAY
	end
	return L.AGO_DAYS:format(days)
end

-- "today 23:10", "yesterday 23:10", "12 Oct 23:10" (local time).
function Util.FormatWhen(t, now)
	if type(t) ~= "number" then
		return nil
	end
	local L = ns.L
	now = now or time()
	local clock = date("%H:%M", t)
	local day, today = date("%Y-%m-%d", t), date("%Y-%m-%d", now)
	if day == today then
		return L.WHEN_TODAY:format(clock)
	elseif day == date("%Y-%m-%d", now - 86400) then
		return L.WHEN_YESTERDAY:format(clock)
	end
	return date("%d %b ", t) .. clock
end

function Util.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = Util.DeepCopy(v)
	end
	return out
end

function Util.Clamp(value, low, high)
	value = tonumber(value) or low
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end
