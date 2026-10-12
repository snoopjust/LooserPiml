local H = require("helpers")

-- Registers a handler on client `mock` that records received messages.
local function recorder(mock, msgType)
	local received = {}
	mock.ns.Comm:RegisterHandler({}, msgType, function(_, data, sender, meta)
		received[#received + 1] = { data = data, sender = sender, meta = meta }
	end)
	return received
end

local function sentByPrefix(mock, prefix)
	local count = 0
	for _, call in ipairs(mock.sent) do
		if call.prefix == prefix then
			count = count + 1
		end
	end
	return count
end

describe("Comm", function()
	after_each(H.checkClients)

	describe("encoding", function()
		it("roundtrips nested data through serialize + compress + encode", function()
			local _, ns = H.client()
			local allBytes = {}
			for i = 1, 255 do
				allBytes[i] = string.char(i)
			end
			local envelope = {
				v = 1,
				t = "TEST",
				d = {
					text = "Max died. Again. |cffff0000red|r ~ ^ \\",
					bytes = table.concat(allBytes),
					numbers = { 0, -1, 3.25, 1e10, 2 ^ 31 },
					flags = { yes = true, no = false },
					nested = { a = { b = { c = "deep" } } },
				},
			}
			local encoded = ns.Comm:Encode(envelope)
			assert.is_nil(encoded:find("\0", 1, true))
			assert.are.same(envelope, ns.Comm:Decode(encoded))
		end)

		it("rejects garbage instead of erroring", function()
			local _, ns = H.client()
			assert.is_nil(ns.Comm:Decode("not a valid message"))
			assert.is_nil(ns.Comm:Decode(nil))
			assert.is_nil(ns.Comm:Decode(""))
		end)
	end)

	describe("transport between two clients", function()
		it("delivers small and multi-chunk messages through AceComm", function()
			local clients = H.group({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			local got = recorder(max, "TEST")
			local big = string.rep("0123456789abcdefghijklmnopqrstuvwxyz", 60) .. tostring(os.time())
			assert.are.equal("sent", me.ns.Comm:Send("TEST", { text = "hi" }))
			assert.are.equal("sent", me.ns.Comm:Send("TEST", { text = big, seed = math.random() }))
			me:Advance(5)
			assert.are.equal(2, #got)
			assert.are.equal("hi", got[1].data.text)
			assert.are.equal(big, got[2].data.text)
			assert.are.equal("Me-TestRealm", got[1].sender)
			assert.are.equal("WHISPER", got[1].meta.distribution)
			assert.is_false(got[1].meta.test)
			H.assertNoErrors(me)
			H.assertNoErrors(max)
		end)

		it("whispers each connected friend, also in a raid, and sends nothing when none is online", function()
			local mock, ns = H.client({ confirmed = { "Max" } })
			assert.are.equal("nobody", ns.Comm:Send("TEST", {}))
			mock:JoinGroup({ { name = "Max", class = "WARRIOR" } }, true)
			ns.Comm:Send("TEST", {})
			mock:Advance(1)
			assert.are.equal("WHISPER", mock.sent[#mock.sent].chatType)
			assert.are.equal("Max", mock.sent[#mock.sent].target)
		end)

		it("ignores its own echo, duplicates and other protocols", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			local got = recorder(mock, "TEST")
			ns.Comm:Send("TEST", { n = 1 }) -- echoed back by the mock server
			mock:Advance(1)
			assert.are.equal(0, #got)

			local text = ns.Comm:Encode({ v = 1, t = "TEST", s = 7, id = 1, d = { n = 2 } })
			mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Max-TestRealm")
			mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Max-TestRealm")
			assert.are.equal(1, #got)

			local future = ns.Comm:Encode({ v = 99, t = "TEST", s = 7, id = 2, d = {} })
			mock:Fire("CHAT_MSG_ADDON", "LPiml", future, "PARTY", "Max-TestRealm")
			mock:Fire("CHAT_MSG_ADDON", "LPiml", "garbage", "PARTY", "Max-TestRealm")
			mock:Fire("CHAT_MSG_ADDON", "OtherAddon", text, "PARTY", "Max-TestRealm")
			assert.are.equal(1, #got)
			H.assertNoErrors(mock)
		end)

		it("accepts the same id again after the sender reloaded (new session)", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, friends = { "Max" } })
			local got = recorder(mock, "TEST")
			mock:Fire("CHAT_MSG_ADDON", "LPiml", ns.Comm:Encode({ v = 1, t = "TEST", s = 1, id = 1, d = {} }), "PARTY", "Max-TestRealm")
			mock:Fire("CHAT_MSG_ADDON", "LPiml", ns.Comm:Encode({ v = 1, t = "TEST", s = 2, id = 1, d = {} }), "PARTY", "Max-TestRealm")
			assert.are.equal(2, #got)
		end)
	end)

	describe("restrictions", function()
		it("holds messages during an encounter and flushes them afterwards, marked late", function()
			local clients = H.group({ { name = "Me" }, { name = "Max", class = "WARRIOR" } })
			local me, max = clients[1], clients[2]
			local got = recorder(max, "TEST")
			local before = sentByPrefix(me, "LPiml")

			me:StartEncounter()
			assert.are.equal("queued", me.ns.Comm:Send("TEST", { n = 1 }))
			assert.are.equal("queued", me.ns.Comm:Send("TEST", { n = 2 }))
			me:Advance(30)
			assert.are.equal(before, sentByPrefix(me, "LPiml"))
			assert.are.equal(0, #me.refused) -- we never even tried
			assert.are.equal(0, #got)

			me:EndEncounter()
			me:Advance(3)
			assert.are.equal(2, #got)
			assert.are.equal(1, got[1].data.n) -- order kept
			assert.are.equal(2, got[2].data.n)
			assert.are.equal("encounter", got[1].meta.late)
			assert.are.equal(0, #me.ns.Comm.queue)
			H.assertNoErrors(me)
			H.assertNoErrors(max)
		end)

		it("holds while InChatMessagingLockdown() is true and flushes when the restriction lifts", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			ns:GetModule("Stats").db.share = false -- only this test's own traffic
			local before = #mock.sent
			mock.lockdown = true
			assert.are.equal("queued", ns.Comm:Send("TEST", {}))
			mock:Advance(12)
			assert.are.equal(before, #mock.sent)
			mock.lockdown = false
			mock:Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
			mock:Advance(2)
			assert.are.equal(before + 1, #mock.sent)
		end)

		it("re-queues a message the client refused and retries it", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			mock.refuseSends = true -- e.g. AddOnMessageLockdown without InChatMessagingLockdown
			assert.are.equal("sent", ns.Comm:Send("TEST", { n = 1 }))
			mock:Advance(1)
			assert.are.equal(1, #ns.Comm.queue)
			assert.is_true(#mock.refused >= 1)

			mock.refuseSends = false
			mock:Advance(ns.Comm.RETRY_INTERVAL + 1)
			assert.are.equal(0, #ns.Comm.queue)
			local last = ns.Comm:Decode(mock.sent[#mock.sent].text)
			assert.are.equal(1, last.d.n)
			H.assertNoErrors(mock)
		end)

		it("gives up after MAX_ATTEMPTS refused sends", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, confirmed = { "Max" } })
			ns:GetModule("Stats").db.share = false -- only this test's own traffic
			mock.refuseSends = true
			ns.Comm:Send("TEST", {})
			mock:Advance(ns.Comm.RETRY_INTERVAL * (ns.Comm.MAX_ATTEMPTS + 2))
			assert.are.equal(0, #ns.Comm.queue)
			assert.are.equal(ns.Comm.MAX_ATTEMPTS, #mock.refused)
			assert.is_nil(ns.Comm.retryTicker)
		end)

		it("drops held messages that became stale", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			ns:GetModule("Stats").db.share = false -- only this test's own traffic
			local before = #mock.sent
			mock.lockdown = true
			ns.Comm:Send("TEST", {})
			mock.now = mock.now + ns.Comm.MAX_AGE + 10
			mock.lockdown = false
			ns.Comm:Flush()
			assert.are.equal(0, #ns.Comm.queue)
			mock:Advance(1)
			assert.are.equal(before, #mock.sent)
		end)

		it("replaces a held message with a newer one that has the same key", function()
			local _, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			ns.Events:SetSimulatedEncounter(true, "Boss")
			ns.Comm:Send("TEST", { n = 1 }, { prio = "BULK", key = "snap" })
			ns.Comm:Send("OTHER", { n = 2 })
			ns.Comm:Send("TEST", { n = 3 }, { prio = "BULK", key = "snap" })
			assert.are.equal(2, #ns.Comm.queue)
			assert.are.equal("OTHER", ns.Comm.queue[1].t)
			assert.are.equal(3, ns.Comm.queue[2].d.n)
			-- a failed retry of an older snapshot must not replace the newer one
			local old = { t = "TEST", d = { n = 0 }, id = 0, key = "snap", attempts = 1, queuedAt = 0 }
			ns.Comm:Hold(old, true)
			assert.are.equal(2, #ns.Comm.queue)
			assert.are.equal(3, ns.Comm.queue[2].d.n)
		end)

		it("caps the queue at MAX_QUEUE, dropping the oldest", function()
			local _, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			ns.Events:SetSimulatedEncounter(true, "Boss")
			for i = 1, ns.Comm.MAX_QUEUE + 5 do
				ns.Comm:Send("TEST", { n = i })
			end
			assert.are.equal(ns.Comm.MAX_QUEUE, #ns.Comm.queue)
			assert.are.equal(6, ns.Comm.queue[1].d.n)
		end)

		it("does not flush into a group that no longer exists", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			local before = #mock.sent
			mock:StartEncounter()
			ns.Comm:Send("TEST", {})
			mock:LeaveGroup()
			mock:EndEncounter()
			mock:Advance(3)
			assert.are.equal(before, #mock.sent)
			assert.are.equal(0, #ns.Comm.queue)
		end)
	end)

	describe("test mode", function()
		it("loops back locally and never touches SendAddonMessage", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } }, testMode = true })
			local before = #mock.sent
			assert.are.equal("loopback", ns.Comm:Send("TEST", {}))
			mock:Advance(2)
			assert.are.equal(before, #mock.sent)
		end)

		it("SimulateReceive runs the real decode/dispatch path, tagged as test", function()
			local _, ns = H.client({ testMode = true })
			local got = {}
			ns.Comm:RegisterHandler({}, "TEST", function(_, data, sender, meta)
				got[#got + 1] = { data = data, sender = sender, meta = meta }
			end)
			ns.Comm:SimulateReceive("Max", "TEST", { x = 1 }, "encounter")
			assert.are.equal(1, #got)
			assert.are.equal("Max-TestRealm", got[1].sender)
			assert.is_true(got[1].meta.test)
			assert.are.equal("encounter", got[1].meta.late)
		end)
	end)
end)
