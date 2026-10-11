-- Central event dispatcher.
--
-- Events:Register(owner, event[, handler]) - handler is a function
-- (owner, event, ...) or a method name on owner (defaults to the event name).
-- Names starting with "LP_" are internal messages sent with Events:Fire.
--
-- Also tracks boss encounters, because both Comm (hold outgoing messages)
-- and Display (hold banners) need to know about them.
local _, ns = ...

local Events = {}
ns:RegisterCore("Events", Events)

local frame = CreateFrame("Frame")
local listeners = {} -- event -> array of { owner, fn }

local function isInternal(event)
	return event:sub(1, 3) == "LP_"
end

local function isValidEvent(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event)
	end
	return true
end

function Events:Register(owner, event, handler)
	handler = handler or event
	local fn = type(handler) == "function" and handler or owner[handler]
	assert(type(fn) == "function", "no handler for " .. tostring(event))

	local list = listeners[event]
	if not list then
		if not isInternal(event) then
			if not isValidEvent(event) then
				-- Forever lacks some Retail events; skip instead of erroring.
				ns.Log:Debug("Event %s does not exist on this client, skipped", event)
				return false
			end
			frame:RegisterEvent(event)
		end
		list = {}
		listeners[event] = list
	end
	for _, entry in ipairs(list) do
		if entry.owner == owner then
			entry.fn = fn
			return true
		end
	end
	list[#list + 1] = { owner = owner, fn = fn }
	return true
end

function Events:Unregister(owner, event)
	local list = listeners[event]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i].owner == owner then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		listeners[event] = nil
		if not isInternal(event) then
			frame:UnregisterEvent(event)
		end
	end
end

function Events:UnregisterAll(owner)
	local events = {}
	for event in pairs(listeners) do
		events[#events + 1] = event
	end
	for _, event in ipairs(events) do
		self:Unregister(owner, event)
	end
end

function Events:IsRegistered(owner, event)
	for _, entry in ipairs(listeners[event] or {}) do
		if entry.owner == owner then
			return true
		end
	end
	return false
end

local function dispatch(event, ...)
	local list = listeners[event]
	if not list then
		return
	end
	-- Copy, so handlers can (un)register while we iterate.
	local snapshot = {}
	for i = 1, #list do
		snapshot[i] = list[i]
	end
	for i = 1, #snapshot do
		local entry = snapshot[i]
		ns.SafeCall(entry.fn, entry.owner, event, ...)
	end
end

-- Internal messages (LP_*). Also usable in tests to inject game events.
function Events:Fire(event, ...)
	dispatch(event, ...)
end

frame:SetScript("OnEvent", function(_, event, ...)
	dispatch(event, ...)
end)

----------------------------------------------------------------------
-- Encounter state
----------------------------------------------------------------------
-- Fires LP_ENCOUNTER_START(name) / LP_ENCOUNTER_END(name, success).

local encounter = { real = false, simulated = false, name = nil }

local function clientSaysEncounter()
	local fn = (C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress) or IsEncounterInProgress
	if not fn then
		return false
	end
	local inProgress = fn()
	if ns.IsSecret(inProgress) then
		return true -- can't tell; be conservative and treat it as running
	end
	return inProgress and true or false
end

function Events:IsEncounterActive()
	return encounter.real or encounter.simulated or clientSaysEncounter()
end

function Events:GetEncounterName()
	return encounter.name
end

local function safeName(name)
	if type(name) == "string" and not ns.IsSecret(name) then
		return name
	end
	return nil
end

function Events:ENCOUNTER_START(_, _, encounterName)
	encounter.real = true
	encounter.name = safeName(encounterName)
	ns.Log:Debug("Encounter started: %s", tostring(encounter.name))
	self:Fire("LP_ENCOUNTER_START", encounter.name)
end

function Events:ENCOUNTER_END(_, _, encounterName, _, _, success)
	encounter.real = false
	local name = safeName(encounterName) or encounter.name
	ns.Log:Debug("Encounter ended: %s", tostring(name))
	if not encounter.simulated then
		encounter.name = nil
	end
	self:Fire("LP_ENCOUNTER_END", name, not ns.IsSecret(success) and success == 1)
end

-- Safety net: if ENCOUNTER_END got lost (disconnect, zoning), don't hold
-- messages forever.
function Events:PLAYER_ENTERING_WORLD()
	if encounter.real and not clientSaysEncounter() then
		self:ENCOUNTER_END("ENCOUNTER_END", nil, encounter.name, nil, nil, 0)
	end
end

-- Test mode: pretend a boss fight starts/ends.
function Events:SetSimulatedEncounter(active, name)
	if active == encounter.simulated then
		return
	end
	encounter.simulated = active
	if active then
		encounter.name = name
		self:Fire("LP_ENCOUNTER_START", name)
	else
		local ended = encounter.name
		if not encounter.real then
			encounter.name = nil
		end
		self:Fire("LP_ENCOUNTER_END", ended, true)
	end
end

function Events:OnEnable()
	self:Register(self, "ENCOUNTER_START")
	self:Register(self, "ENCOUNTER_END")
	self:Register(self, "PLAYER_ENTERING_WORLD")
end
