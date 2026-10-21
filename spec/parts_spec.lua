local H = require("helpers")

-- Large messages as LooserPiml's own numbered parts (Comm:SendText).
-- In-game (Forever beta, 2026-10-20) AceComm's multi-part messages arrived
-- damaged ("bad compression") while single messages were fine. These specs
-- let the mock server cut full-size messages, lose parts or reorder them.

local function stats(mock)
	return mock.ns:GetModule("Stats")
end

local function pair()
	local clients, net = H.friends({ { name = "Me", class = "HUNTER" }, { name = "Max", class = "WARRIOR" } })
	return clients[1], clients[2], net
end

-- A STATS message that needs several parts: lots of ranked duels.
local function bigStats(mock)
	local _, ranked = stats(mock).Duels:GetRecords()
	for i = 1, 40 do
		ranked[i] = { i = string.format("%08x", i * 2654435761 % 4294967296), t = 1760000000 + i * 600, o = "Max-TestRealm", w = i % 2 == 0 }
	end
end

local function lpMessages(mock)
	local out = {}
	for _, call in ipairs(mock.sent) do
		if call.prefix == "LPiml" then
			out[#out + 1] = call
		end
	end
	return out
end

describe("Large messages as numbered parts", function()
	after_each(H.checkClients)

	it("sends large messages as small single messages, never AceComm chunks", function()
		local me, max, net = pair()
		me.sent = {}
		bigStats(me)
		stats(me):Changed()
		net:Advance(40)
		local parts = 0
		for _, call in ipairs(lpMessages(me)) do
			assert.is_true(#call.text <= 230, "part of " .. #call.text .. " bytes")
			assert.is_nil(call.text:match("^[\001-\003]"), "an AceComm multi-part chunk was sent")
			if call.text:find("^LPP") then
				parts = parts + 1
			end
		end
		assert.is_true(parts >= 3, "expected several parts, got " .. parts)
		assert.are.equal(40, #max.ns:GetModule("Stats").db.friendStats["Me-TestRealm"].duel.r)
	end)

	it("arrives intact when the server cuts full-size (255 byte) messages", function()
		local me, max, net = pair()
		net.transform = function(pending)
			for _, msg in ipairs(pending) do
				if #msg.text >= 250 then
					msg.text = msg.text:sub(1, 245)
				end
			end
			return pending
		end
		bigStats(me)
		stats(me):Changed()
		net:Advance(40)
		assert.are.equal(40, #stats(max).db.friendStats["Me-TestRealm"].duel.r)
		assert.is_false(max:ChatContains("bad compression"))
	end)

	it("puts parts back together in order even when they arrive out of order", function()
		local me, max, net = pair()
		local held = {}
		net.transform = function(pending)
			local out = {}
			for _, msg in ipairs(pending) do
				if msg.text:find("^LPP%w+:1/") then
					held[#held + 1] = msg -- every first part comes last
				else
					out[#out + 1] = msg
				end
			end
			if #out == 0 and #held > 0 then
				out, held = held, {}
			end
			return out
		end
		bigStats(me)
		stats(me):Changed()
		net:Advance(40)
		assert.are.equal(40, #stats(max).db.friendStats["Me-TestRealm"].duel.r)
	end)

	it("logs which part never arrived and drops the incomplete message", function()
		local me, max, net = pair()
		max.ns.Log:SetDebug(true)
		net.transform = function(pending)
			local out = {}
			for _, msg in ipairs(pending) do
				if not msg.text:find("^LPP%w+:2/") then
					out[#out + 1] = msg
				end
			end
			return out
		end
		bigStats(me)
		stats(me):Changed()
		net:Advance(100)
		assert.is_nil((stats(max).db.friendStats["Me-TestRealm"] or {}).duel)
		local found = false
		for _, line in ipairs(max.chat) do
			if line:find("Incomplete message from Me%-TestRealm: %d+ of %d+ parts arrived, missing 2") then
				found = true
			end
		end
		assert.is_true(found, "no 'Incomplete message' log line")
	end)

	it("tells the player once, without debug mode, when a friend's messages arrive incomplete or damaged", function()
		local me, max, net = pair()
		net.transform = function(pending)
			local out = {}
			for _, msg in ipairs(pending) do
				if not msg.text:find("^LPP%w+:2/") then
					out[#out + 1] = msg
				end
			end
			return out
		end
		bigStats(me)
		for _ = 1, 2 do
			stats(me):Changed()
			net:Advance(100)
		end
		local function count(fragment)
			local n = 0
			for _, line in ipairs(max.chat) do
				if line:find(fragment, 1, true) then
					n = n + 1
				end
			end
			return n
		end
		assert.are.equal(1, count("arrived incomplete and was skipped"))
		assert.is_true(max:ChatContains("/lp selftest"))
		-- a damaged single message: its own hint, also once
		for _ = 1, 3 do
			max:Fire("CHAT_MSG_ADDON", "LPiml", "not a LooserPiml message", "WHISPER", "Me", "Me", 0, 0, "", 0)
		end
		assert.are.equal(1, count("arrived damaged and was skipped"))
	end)

	it("ignores parts from players who aren't on the list", function()
		local mock, ns = H.client({ friends = { "Max" } })
		ns.Comm:OnCommReceived("LPiml", "LPP1a:1/2:abc", "WHISPER", "Stranger")
		ns.Comm:OnCommReceived("LPiml", "LPP1a:2/2:def", "WHISPER", "Stranger")
		assert.are.same({}, ns.Comm.partial)
		-- garbage from a friend: refused, nothing kept
		ns.Comm:OnCommReceived("LPiml", "LPP1a:5/2:x", "WHISPER", "Max")
		ns.Comm:OnCommReceived("LPiml", "LPP1a:1/999:x", "WHISPER", "Max")
		assert.are.same({}, ns.Comm.partial)
	end)

	it("doesn't send parts still due to a friend removed meanwhile", function()
		local me, max, net = pair()
		bigStats(me)
		stats(me):Changed()
		net:Advance(0.3) -- the first part is out
		me.ns.Friends:Remove("Max")
		local before = #lpMessages(me)
		net:Advance(10)
		assert.are.equal(before, #lpMessages(me))
	end)
end)
