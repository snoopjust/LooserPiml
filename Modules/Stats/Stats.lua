-- Stats: records what happens to the own character, keeps aggregates per
-- period and shares them (never the raw log) with friends.
--
-- Files:
--   Stats.lua       this module: storage, recording, compaction, friends cache
--   Model.lua       pure data model (periods, aggregates, rollup) - no game API
--   (more files are added as the module grows)
local _, ns = ...

local Stats = ns:NewModule("Stats")

Stats.defaults = {
	chars = {},   -- ["Name-Realm"] = per-character log, buckets, counters
	friends = {}, -- ["Name-Realm"] = cached aggregates received from friends
}

function Stats:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, self.defaults)
end
