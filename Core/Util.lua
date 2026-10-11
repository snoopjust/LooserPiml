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
