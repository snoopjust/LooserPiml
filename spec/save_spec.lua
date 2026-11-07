local H = require("helpers")

-- Core/SaveReminder.lua: the game saves addon data only on logout or
-- /reload, a crash loses everything since then (launch weekend 2026-11-06).

local function prompts(mock)
	local n = 0
	for _, which in ipairs(mock.popups) do
		if which == "LOOSERPIML_SAVE" then
			n = n + 1
		end
	end
	return n
end

local function dialog(mock)
	return mock.env.StaticPopupDialogs.LOOSERPIML_SAVE
end

describe("Save reminder", function()
	after_each(H.checkClients)

	it("asks to save at the next quiet moment after a friend was added; only the button reloads", function()
		local mock, ns = H.client()
		mock:Advance(60)
		assert.are.equal(0, prompts(mock))
		assert(ns.Friends:Add("Max"))
		mock:Advance(31)
		assert.are.equal(1, prompts(mock))
		assert.is_truthy(dialog(mock).text:find("you added a friend", 1, true))
		assert.is_true(mock:ChatContains("/reload saves your LooserPiml friends"))
		assert.are.equal(0, mock.reloads) -- nothing happens on its own
		mock:Advance(300)
		assert.are.equal(1, prompts(mock)) -- one dialog, not a new one every check
		mock:UserAction(function()
			dialog(mock).OnAccept()
		end)
		assert.are.equal(1, mock.reloads)
	end)

	it("waits while fighting, in an instance, during a boss or while dead", function()
		local mock, ns = H.client()
		mock.inCombat = true
		assert(ns.Friends:Add("Max"))
		mock:Advance(120)
		assert.are.equal(0, prompts(mock))
		mock.inCombat = false
		mock:EnterInstance("The Deadmines", "party", 36)
		mock:Advance(120)
		assert.are.equal(0, prompts(mock))
		mock:LeaveInstance()
		mock.player.dead = true
		mock:Advance(120)
		assert.are.equal(0, prompts(mock))
		mock.player.dead = false
		mock:Advance(31)
		assert.are.equal(1, prompts(mock))
	end)

	it("reminds about once an hour, and 'Later' asks again after 20 minutes", function()
		local mock = H.client()
		mock:Advance(59 * 60)
		assert.are.equal(0, prompts(mock))
		mock:Advance(2 * 60)
		assert.are.equal(1, prompts(mock))
		assert.is_truthy(dialog(mock).text:find("save your friends list and stats now", 1, true))
		dialog(mock).OnCancel() -- "Later" (Escape works the same)
		mock:Advance(19 * 60)
		assert.are.equal(1, prompts(mock))
		mock:Advance(2 * 60)
		assert.are.equal(2, prompts(mock))
		assert.are.equal(0, mock.reloads)
	end)

	it("starts counting again after a /reload or login", function()
		local mock = H.client()
		mock:Advance(50 * 60)
		local reloaded = H.client({ savedVariables = mock.env.LooserPimlDB })
		reloaded:Advance(30 * 60)
		assert.are.equal(0, prompts(reloaded))
	end)

	it("stays quiet with the setting off and in test mode", function()
		local mock, ns = H.client()
		ns.Options:Set("save.reminder", false)
		assert.is_false(mock.env.LooserPimlDB.saveReminder)
		assert(ns.Friends:Add("Max"))
		mock:Advance(2 * 3600)
		assert.are.equal(0, prompts(mock))
		local test, tns = H.client({ testMode = true })
		test:Advance(2 * 3600)
		assert.are.equal(0, prompts(test))
		assert.is_true(tns.Options:Get("save.reminder"))
	end)
end)

describe("Friends who have you on their list but aren't on yours", function()
	after_each(H.checkClients)

	it("shows one hint per name and session, never answers and never adds them", function()
		-- Max lists Me; Me's list was lost (empty)
		local clients, net = H.friends({ { name = "Me", friends = {} }, { name = "Max", class = "WARRIOR" } })
		local me, max = clients[1], clients[2]
		local function hints()
			local n = 0
			for _, line in ipairs(me.chat) do
				if line:find("has you on their LooserPiml friends list", 1, true) then
					n = n + 1
				end
			end
			return n
		end
		assert.are.equal(1, hints())
		assert.is_true(me:ChatContains("Max"))
		-- Max keeps greeting (he comes online again): no second hint
		max.ns.Version.lastGreet = {}
		max.ns.Friends.confirmed = {}
		max:Fire("FRIENDLIST_UPDATE")
		net:Advance(30)
		assert.are.equal(1, hints())
		assert.are.equal(0, #me.sent) -- no answer of any kind
		assert.is_false(me.ns.Friends:IsListed("Max"))
	end)

	it("hints about at most five different names per session", function()
		local mock, ns = H.client()
		for _, name in ipairs({ "Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg" }) do
			ns.Comm:OnCommReceived("LPiml", "garbage", "WHISPER", name)
		end
		local n = 0
		for _, line in ipairs(mock.chat) do
			if line:find("has you on their LooserPiml friends list", 1, true) then
				n = n + 1
			end
		end
		assert.are.equal(5, n)
		assert.are.equal(0, #mock.sent)
	end)
end)
