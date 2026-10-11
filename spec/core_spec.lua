local H = require("helpers")

describe("Core", function()
	after_each(H.checkClients)

	it("loads all .toc files and boots without Lua errors", function()
		local mock, ns = H.client()
		assert.is_true(ns.initialized)
		assert.is_true(ns.loggedIn)
		assert.is_true(ns:GetModule("Ticker"):IsEnabled())
		assert.is_true(mock.prefixes["LPiml"])
		assert.is_function(mock.env.SlashCmdList.LOOSERPIML)
		assert.are.equal("/lp", mock.env.SLASH_LOOSERPIML1)
		H.assertNoErrors(mock)
	end)

	it("only loads files that exist and keeps libraries before addon code", function()
		local files = H.tocFiles()
		assert.are.equal("Libs/LibStub/LibStub.lua", files[1])
		local sawCore = false
		for _, path in ipairs(files) do
			if path:find("^Core/") then
				sawCore = true
			elseif path:find("^Libs/") then
				assert.is_false(sawCore, path .. " is loaded after addon code")
			end
		end
	end)

	describe("DB", function()
		it("creates a fresh database at the current schema", function()
			local mock, ns = H.client()
			local db = mock.env.LooserPimlDB
			assert.are.equal(ns.DB.SCHEMA_VERSION, db.schemaVersion)
			assert.is_false(db.debug)
			assert.is_table(db.modules.Ticker.stats)
		end)

		it("runs migrations in order from the saved schema", function()
			local mock = H.Mock.new()
			local ns = H.load(mock)
			local steps = {}
			ns.DB.SCHEMA_VERSION = 3
			ns.DB.migrations[2] = function(db)
				steps[#steps + 1] = 2
				db.renamed = db.oldName
				db.oldName = nil
			end
			ns.DB.migrations[3] = function()
				steps[#steps + 1] = 3
			end
			mock.env.LooserPimlDB = { schemaVersion = 1, oldName = "x" }
			mock:Fire("ADDON_LOADED", "LooserPiml")
			assert.are.same({ 2, 3 }, steps)
			assert.are.equal(3, mock.env.LooserPimlDB.schemaVersion)
			assert.are.equal("x", mock.env.LooserPimlDB.renamed)
			assert.is_nil(mock.env.LooserPimlDB.oldName)
			H.assertNoErrors(mock)
		end)

		it("leaves data from a newer schema untouched", function()
			local saved = { schemaVersion = 99, debug = false, modules = {} }
			local mock, ns = H.client({ savedVariables = saved })
			assert.are.equal(99, mock.env.LooserPimlDB.schemaVersion)
			assert.are.equal(99, ns.DB.newerSchema)
		end)

		it("keeps settings across a reload", function()
			local mock, ns = H.client()
			ns.Slash:Dispatch("debug on")
			local saved = mock.env.LooserPimlDB
			local mock2, ns2 = H.client({ savedVariables = saved })
			assert.is_true(ns2.Log:IsDebug())
			H.assertNoErrors(mock2)
		end)
	end)

	describe("modules", function()
		it("can be disabled and re-enabled at runtime, cleaning up registrations", function()
			local mock, ns = H.client()
			local ticker = ns:GetModule("Ticker")
			assert.is_true(ns.Events:IsRegistered(ticker, "PLAYER_DEAD"))
			ns:SetModuleEnabled("Ticker", false)
			assert.is_false(ticker:IsEnabled())
			assert.is_false(ns.Events:IsRegistered(ticker, "PLAYER_DEAD"))
			assert.is_false(mock.env.LooserPimlDB.moduleEnabled.Ticker)
			mock:Fire("PLAYER_DEAD")
			assert.are.equal(0, #mock.rendered)
			ns:SetModuleEnabled("Ticker", true)
			assert.is_true(ns.Events:IsRegistered(ticker, "PLAYER_DEAD"))
			H.assertNoErrors(mock)
		end)
	end)

	describe("events", function()
		it("isolates handler errors and reports them to the error handler and log", function()
			local mock, ns = H.client()
			local ranSecond = false
			local a, b = {}, {}
			ns.Events:Register(a, "LP_TEST", function()
				error("boom")
			end)
			ns.Events:Register(b, "LP_TEST", function()
				ranSecond = true
			end)
			ns.Events:Fire("LP_TEST")
			assert.is_true(ranSecond)
			assert.are.equal(1, #mock.errors)
			assert.matches("boom", mock.errors[1])
			assert.are.equal(1, ns.Log.counts.errors)
			mock.errors = {} -- expected
		end)

		it("skips events the client does not know instead of erroring", function()
			local mock = H.Mock.new({ invalidEvents = { ADDON_RESTRICTION_STATE_CHANGED = true } })
			H.load(mock)
			mock:Fire("ADDON_LOADED", "LooserPiml")
			mock.loggedIn = true
			mock:Fire("PLAYER_LOGIN")
			H.assertNoErrors(mock)
		end)
	end)

	describe("log", function()
		it("shows our blocked actions in debug mode", function()
			local mock, ns = H.client({ debug = true })
			mock:Fire("ADDON_ACTION_BLOCKED", "LooserPiml", "CastSpellByName()")
			assert.are.equal(1, ns.Log.counts.blocked)
			assert.is_true(mock:ChatContains("Blocked action: LooserPiml tried to call CastSpellByName()"))
		end)

		it("records but does not print other addons' blocked actions", function()
			local mock, ns = H.client({ debug = true })
			mock:Fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "TargetUnit()")
			assert.are.equal(1, ns.Log.counts.forbidden)
			assert.is_false(mock:ChatContains("SomeOtherAddon"))
		end)

		it("prints blocked actions in test mode too, but not in normal mode", function()
			local mock = H.client()
			mock:Fire("ADDON_ACTION_BLOCKED", "LooserPiml", "Foo()")
			assert.is_false(mock:ChatContains("Blocked action"))
			mock.ns.TestMode:Enable()
			mock:Fire("ADDON_ACTION_BLOCKED", "LooserPiml", "Bar()")
			assert.is_true(mock:ChatContains("tried to call Bar()"))
		end)

		it("captures our Lua errors through the error handler hook in debug mode", function()
			local mock, ns = H.client({ debug = true })
			mock.errorHandler("Interface/AddOns/LooserPiml/Modules/Ticker/Display.lua:1: oops")
			assert.is_true(mock:ChatContains("oops"))
			assert.are.equal(1, ns.Log.counts.errors)
			mock.errors = {} -- expected
		end)
	end)

	describe("hygiene", function()
		it("creates only the globals it is supposed to", function()
			local mock = H.client({ testMode = true, group = { { name = "Max", class = "WARRIOR" } } })
			mock.ns.Slash:Dispatch("sim death Max")
			mock:Advance(10)
			local allowed = {
				_G = true, LibStub = true, ChatThrottleLib = true, AceComm30Frame = true,
				LooserPimlDB = true, LooserPimlBanner = true,
				SLASH_LOOSERPIML1 = true, SLASH_LOOSERPIML2 = true,
				BNSendGameData = true, -- ChatThrottleLib's hooksecurefunc replaces it (as in the game)
			}
			local leaked = {}
			for key in pairs(mock.env) do
				if not allowed[key] then
					leaked[#leaked + 1] = tostring(key)
				end
			end
			table.sort(leaked)
			assert.are.same({}, leaked)
		end)

		it("skips group members whose identity is secret instead of erroring", function()
			local mock, ns = H.client()
			mock:JoinGroup({ { name = H.Mock.Secret(), class = "WARRIOR" }, { name = "Lena", class = H.Mock.Secret() } })
			assert.is_nil(ns.Roster.members["Max-TestRealm"])
			assert.is_not_nil(ns.Roster.members["Lena-TestRealm"])
			assert.is_nil(ns.Roster.members["Lena-TestRealm"].class)
		end)

		it("treats a secret encounter state as 'restricted'", function()
			local mock, ns = H.client({ group = { { name = "Max", class = "WARRIOR" } } })
			mock.env.C_InstanceEncounter.IsEncounterInProgress = function()
				return H.Mock.Secret()
			end
			assert.are.equal("queued", ns.Comm:Send("TEST", {}))
		end)
	end)

	describe("slash", function()
		it("prints help for /lp and unknown commands", function()
			local mock, ns = H.client()
			ns.Slash:Dispatch("")
			assert.is_true(mock:ChatContains("/lp stats"))
			assert.is_true(mock:ChatContains("/lp selftest"))
			ns.Slash:Dispatch("nope")
			assert.is_true(mock:ChatContains("Unknown command 'nope'"))
		end)

		it("toggles debug and test mode", function()
			local mock, ns = H.client()
			mock.env.SlashCmdList.LOOSERPIML("debug on")
			assert.is_true(ns.Log:IsDebug())
			mock.env.SlashCmdList.LOOSERPIML("test on")
			assert.is_true(ns.TestMode:IsEnabled())
			mock.env.SlashCmdList.LOOSERPIML("test off")
			assert.is_false(ns.TestMode:IsEnabled())
			H.assertNoErrors(mock)
		end)
	end)

	describe("self-test", function()
		it("reports libraries, roundtrip, loopback and the real whisper transport", function()
			local mock, ns = H.client()
			ns.Slash:Dispatch("selftest")
			mock:Advance(2)
			assert.is_true(mock:ChatContains("[OK]|r Libraries: CallbackHandler-1.0"))
			assert.is_true(mock:ChatContains("Serialize + compress roundtrip"))
			assert.is_true(mock:ChatContains("[OK]|r Loopback dispatch"))
			assert.is_true(mock:ChatContains("interface=16001"))
			assert.is_true(mock:ChatContains("Real transport: received after"))
			assert.is_false(mock:ChatContains("[FAIL]"))
			-- the payload really needed several chunks
			local whispers = 0
			for _, call in ipairs(mock.sent) do
				if call.chatType == "WHISPER" then
					whispers = whispers + 1
					assert.are.equal("Me", call.target)
				end
			end
			assert.is_true(whispers >= 3, "expected a multi-chunk whisper, got " .. whispers)
			H.assertNoErrors(mock)
		end)

		it("reports a timeout when the whisper never arrives", function()
			local mock, ns = H.client()
			mock.net.Flush = function(net)
				net.pending = {} -- the server swallows everything
			end
			ns.Slash:Dispatch("selftest")
			mock:Advance(11)
			assert.is_true(mock:ChatContains("Real transport: nothing received within 10 s"))
		end)

		it("skips the real transport while addon messages are restricted", function()
			local mock, ns = H.client()
			mock.lockdown = true
			ns.Slash:Dispatch("selftest")
			assert.is_true(mock:ChatContains("Real transport: skipped"))
			assert.are.equal(0, #mock.sent)
		end)
	end)
end)
