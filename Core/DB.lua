-- SavedVariables (LooserPimlDB) with a schema version and migrations.
--
-- Layout:
--   LooserPimlDB = {
--     schemaVersion = 1,
--     debug = false,
--     moduleEnabled = { [moduleName] = bool },  -- only set after a manual toggle
--     modules = { [moduleName] = { ...module data... } },
--   }
--
-- Test mode is deliberately not saved: after a /reload you are back to normal.
--
-- The game reads WTF\Account\<name>\SavedVariables\LooserPiml.lua into the
-- global LooserPimlDB right before our ADDON_LOADED. It writes the global back
-- only on logout or /reload, so a client crash loses the session's changes.
local _, ns = ...

local DB = {}
ns:RegisterCore("DB", DB)

DB.SCHEMA_VERSION = 2

DB.defaults = {
	debug = false,
	moduleEnabled = {},
	modules = {},
}

-- DB.migrations[n] upgrades a database from schema n-1 to n. Add a new entry
-- and bump SCHEMA_VERSION whenever the saved layout changes, e.g.:
--   DB.migrations[3] = function(db) db.modules.Ticker.foo = db.modules.Ticker.bar; db.modules.Ticker.bar = nil end
DB.migrations = {}

-- v0.2.0: banner settings are grouped (hold, size, sound, position), so
-- the v0.1.0 top-level Ticker.sound moves into Ticker.banner.sound.
DB.migrations[2] = function(db)
	local ticker = type(db.modules) == "table" and db.modules.Ticker
	if type(ticker) == "table" and ticker.sound ~= nil then
		ticker.banner = type(ticker.banner) == "table" and ticker.banner or {}
		ticker.banner.sound = ticker.sound
		ticker.sound = nil
	end
end

-- Fills missing keys in dst from src (deep). Existing values win.
local function copyDefaults(src, dst)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then
				dst[key] = {}
			end
			copyDefaults(value, dst[key])
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end
DB.CopyDefaults = copyDefaults

function DB:Migrate(db)
	if db.schemaVersion == nil then
		-- Brand new (empty) database: nothing to migrate. Non-empty data
		-- without a version predates the schema and starts at 0.
		db.schemaVersion = next(db) == nil and self.SCHEMA_VERSION or 0
	end
	local from = db.schemaVersion
	if from > self.SCHEMA_VERSION then
		-- Written by a newer LooserPiml (downgrade). Keep the data untouched.
		self.newerSchema = from
		return
	end
	for version = from + 1, self.SCHEMA_VERSION do
		local step = self.migrations[version]
		if step then
			step(db)
		end
		db.schemaVersion = version
	end
end

function DB:OnInitialize()
	local db = _G.LooserPimlDB
	if type(db) ~= "table" then
		db = {}
	end
	self:Migrate(db)
	copyDefaults(self.defaults, db)
	_G.LooserPimlDB = db
	self.data = db
	if self.newerSchema then
		ns.Log:Warn("Saved data comes from a newer LooserPiml (schema %d > %d). Please update.", self.newerSchema, self.SCHEMA_VERSION)
	end
end

function DB:Get(key)
	return self.data and self.data[key]
end

function DB:Set(key, value)
	self.data[key] = value
end

-- Per-module storage, created on first use and filled with defaults.
function DB:GetModuleDB(name, defaults)
	local modules = self.data.modules
	modules[name] = copyDefaults(defaults or {}, modules[name] or {})
	return modules[name]
end

function DB:IsModuleEnabled(name, default)
	local value = self.data and self.data.moduleEnabled[name]
	if value == nil then
		return default ~= false
	end
	return value
end

function DB:SetModuleEnabled(name, enabled)
	self.data.moduleEnabled[name] = enabled and true or false
end
