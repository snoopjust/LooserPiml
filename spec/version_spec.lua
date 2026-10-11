local H = require("helpers")

local function hello(ns, version, extra)
	local data = { ver = version, proto = ns.Comm.PROTOCOL }
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	return ns.Comm:Encode({ v = ns.Comm.PROTOCOL, t = "HELLO", s = math.random(1, 1e9), id = 1, d = data })
end

describe("Version", function()
	after_each(H.checkClients)

	describe("Parse/Compare", function()
		local Version

		before_each(function()
			local _, ns = H.client()
			Version = ns.Version
		end)

		it("parses tags and packager versions", function()
			assert.are.same({ 1, 2, 3 }, Version.Parse("v1.2.3"))
			assert.are.same({ 1, 2, 0 }, Version.Parse("1.2"))
			assert.are.same({ 0, 3, 1 }, Version.Parse("v0.3.1-beta2"))
			assert.are.same({ 1, 0, 0 }, Version.Parse("v1.0.0-4-gabc123"))
			assert.is_nil(Version.Parse("dev"))
			assert.is_nil(Version.Parse("@project-version@"))
			assert.is_nil(Version.Parse(nil))
		end)

		it("compares numerically, not as strings", function()
			assert.are.equal(-1, Version.Compare("1.2.9", "1.10.0"))
			assert.are.equal(1, Version.Compare("v2.0.0", "1.99.99"))
			assert.are.equal(0, Version.Compare("v1.2", "1.2.0"))
			assert.are.equal(0, Version.Compare("1.2.0-beta", "1.2.0"))
			assert.is_nil(Version.Compare("dev", "1.0.0"))
		end)
	end)

	it("reads its version from the .toc and treats @project-version@ as a dev build", function()
		local _, ns = H.client()
		assert.are.equal("dev", ns.Version:GetCurrent())
		local _, ns2 = H.client({ version = "v0.2.0" })
		assert.are.equal("v0.2.0", ns2.Version:GetCurrent())
	end)

	it("handshakes on login and warns locally about an outdated group member", function()
		local clients = H.group({
			{ name = "Me", version = "v0.2.0" },
			{ name = "Max", class = "WARRIOR", version = "v0.1.0" },
		})
		local me, max = clients[1], clients[2]
		assert.is_true(me:ChatContains("runs an older LooserPiml (v0.1.0, you have v0.2.0)"))
		assert.is_true(max:ChatContains("has a newer LooserPiml (v0.2.0)"))
		assert.are.equal("v0.1.0", me.ns.Version.known["Max-TestRealm"].version)
		H.assertNoErrors(me)
		H.assertNoErrors(max)
	end)

	it("warns only once per player and session", function()
		local mock, ns = H.client({ version = "v0.2.0", group = { { name = "Max", class = "WARRIOR" } } })
		mock:Fire("CHAT_MSG_ADDON", "LPiml", hello(ns, "v0.1.0"), "PARTY", "Max-TestRealm")
		mock:Fire("CHAT_MSG_ADDON", "LPiml", hello(ns, "v0.1.0"), "PARTY", "Max-TestRealm")
		local warnings = 0
		for _, line in ipairs(mock.chat) do
			if line:find("older LooserPiml", 1, true) then
				warnings = warnings + 1
			end
		end
		assert.are.equal(1, warnings)
	end)

	it("replies to a HELLO, but not to a reply", function()
		local mock, ns = H.client({ version = "v0.2.0", group = { { name = "Max", class = "WARRIOR" } } })
		mock:Advance(ns.Version.HELLO_COOLDOWN + 1)
		local before = #mock.sent
		mock:Fire("CHAT_MSG_ADDON", "LPiml", hello(ns, "v0.2.0", { reply = true }), "PARTY", "Max-TestRealm")
		mock:Advance(1)
		assert.are.equal(before, #mock.sent)
		mock:Fire("CHAT_MSG_ADDON", "LPiml", hello(ns, "v0.2.0"), "PARTY", "Max-TestRealm")
		mock:Advance(1)
		assert.are.equal(before + 1, #mock.sent)
		local reply = ns.Comm:Decode(mock.sent[#mock.sent].text)
		assert.are.equal("HELLO", reply.t)
		assert.is_true(reply.d.reply)
	end)

	it("says hello when someone joins, coalescing bursts", function()
		local mock, ns = H.client({ version = "v0.2.0" })
		mock:JoinGroup({ { name = "Max", class = "WARRIOR" } })
		mock:JoinGroup({ { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE" } })
		mock:JoinGroup({ { name = "Max", class = "WARRIOR" }, { name = "Lena", class = "MAGE" }, { name = "Kim", class = "ROGUE" } })
		mock:Advance(1)
		local hellos = 0
		for _, call in ipairs(mock.sent) do
			if ns.Comm:Decode(call.text).t == "HELLO" then
				hellos = hellos + 1
			end
		end
		assert.are.equal(1, hellos)
		mock:Advance(ns.Version.HELLO_COOLDOWN + 1)
		hellos = 0
		for _, call in ipairs(mock.sent) do
			if ns.Comm:Decode(call.text).t == "HELLO" then
				hellos = hellos + 1
			end
		end
		assert.are.equal(2, hellos) -- one coalesced follow-up for the later joins
	end)

	it("strips escape sequences from versions received over the network", function()
		local mock, ns = H.client({ version = "v0.2.0", group = { { name = "Max", class = "WARRIOR" } } })
		mock:Fire("CHAT_MSG_ADDON", "LPiml", hello(ns, "v0.1.0|TInterface\\x:99|t|Hitem:1|h"), "PARTY", "Max-TestRealm")
		assert.are.equal("v0.1.0TInterfacex99tHitem1h", ns.Version.known["Max-TestRealm"].version)
		for _, line in ipairs(mock.chat) do
			assert.is_nil(line:find("|TInterface\\x", 1, true))
		end
	end)

	it("reports an incompatible protocol", function()
		local mock, ns = H.client({ version = "v0.2.0", group = { { name = "Max", class = "WARRIOR" } } })
		local text = ns.Comm:Encode({ v = 2, t = "HELLO", s = 1, id = 1, d = { ver = "v1.0.0", proto = 2 } })
		mock:Fire("CHAT_MSG_ADDON", "LPiml", text, "PARTY", "Max-TestRealm")
		assert.is_true(mock:ChatContains("uses a different message format"))
	end)

	it("never compares dev builds outside test mode", function()
		local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
		mock:Fire("CHAT_MSG_ADDON", "LPiml", hello(ns, "v0.1.0"), "PARTY", "Max-TestRealm")
		assert.is_false(mock:ChatContains("LooserPiml ("))
		assert.is_false(mock:ChatContains("newer LooserPiml"))
	end)

	it("test mode: the fake group includes an outdated and a newer version", function()
		local mock = H.client({ testMode = true })
		mock:Advance(2)
		assert.is_true(mock:ChatContains("runs an older LooserPiml"))
		assert.is_true(mock:ChatContains("has a newer LooserPiml"))
		mock.ns.Slash:Dispatch("version")
		assert.is_true(mock:ChatContains("Your version: dev"))
		H.assertNoErrors(mock)
	end)
end)
