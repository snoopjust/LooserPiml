-- English strings. To localize, copy this file (e.g. deDE.lua), translate the
-- values and load it after this one in the .toc guarded by GetLocale().
--
-- Ticker templates use {tokens}: {name}, {level}, {count}, {zone}, {instance}.
-- Several variants per event; one is picked at random.
local _, ns = ...

local L = setmetatable({}, {
	__index = function(_, key)
		return key -- missing strings show their key instead of erroring
	end,
})
ns.L = L

-- Core ----------------------------------------------------------------
L.ADDON_PREFIX = "|cff33ff99LooserPiml|r"
L.CHAT_TAG = "|cff33ff99[LP]|r"
L.TEST_TAG = "|cff999999[test]|r"
L.ON = "on"
L.OFF = "off"

L.HELP_HEADER = "Commands:"
L.HELP_STATS = "show the death and level-up ranking"
L.HELP_TEST = "test mode: messages loop back locally, fake group members"
L.HELP_SIM = "simulate an event (death, drown, levelup, enter, leave, boss)"
L.HELP_SELFTEST = "check libraries, encoding and the real addon-message transport"
L.HELP_DEBUG = "debug logging, incl. blocked actions and Lua errors"
L.HELP_VERSION = "show your version and the versions in your group"
L.HELP_LOG = "print the recent debug log"
L.SLASH_UNKNOWN = "Unknown command '%s'."

L.DEBUG_STATE = "Debug mode: %s"
L.TEST_ON = "Test mode ON. Nothing is sent to other players; messages loop back locally. Fake group: %s. Try /lp sim death Max"
L.TEST_OFF = "Test mode OFF."
L.TEST_STATE = "Test mode: %s"
L.SIM_NEEDS_TEST = "Simulations only run in test mode: /lp test on"
L.SIM_USAGE = "Usage: /lp sim <%s> [name]"
L.SIM_BOSS_START = "Simulated boss encounter started (%d s). Banners are held until it ends."
L.SIM_BOSS_END = "Simulated boss encounter ended."
L.SIM_BOSS_NAME = "Test Boss"
L.SIM_DUNGEON = "The Deadmines"
L.LOG_HEADER = "Last %d log entries:"
L.LOG_EMPTY = "Log is empty."

L.BLOCKED_ACTION = "Blocked action: %s tried to call %s"
L.FORBIDDEN_ACTION = "Forbidden action: %s tried to call %s"

-- Version -------------------------------------------------------------
L.VERSION_SELF = "Your version: %s (protocol %d)"
L.VERSION_MEMBER = "  %s: %s"
L.VERSION_NONE = "  No other LooserPiml users seen in your group yet."
L.VERSION_UNKNOWN = "no reply"
L.VERSION_OLDER = "%s runs an older LooserPiml (%s, you have %s). Tell them to update in WowUp."
L.VERSION_NEWER = "%s has a newer LooserPiml (%s). Please update in WowUp."
L.VERSION_INCOMPATIBLE = "%s runs LooserPiml %s, which uses a different message format. Ticker events between you are ignored until you both update."

-- Self-test -----------------------------------------------------------
L.SELFTEST_HEADER = "Self-test:"
L.SELFTEST_OK = "|cff00ff00[OK]|r %s"
L.SELFTEST_FAIL = "|cffff3333[FAIL]|r %s"
L.SELFTEST_INFO = "|cffffff00[INFO]|r %s"
L.SELFTEST_LIBS = "Libraries: %s"
L.SELFTEST_LIBS_MISSING = "Missing libraries: %s"
L.SELFTEST_ROUNDTRIP = "Serialize + compress roundtrip (%d bytes on the wire, %d chunks)"
L.SELFTEST_ROUNDTRIP_FAIL = "Serialize + compress roundtrip failed"
L.SELFTEST_LOOPBACK = "Loopback dispatch"
L.SELFTEST_LOOPBACK_FAIL = "Loopback dispatch: handler not reached"
L.SELFTEST_APIS = "Client APIs: %s"
L.SELFTEST_TRANSPORT_SENT = "Real transport: whispered %d bytes (%d chunks) to yourself, waiting up to %d s ..."
L.SELFTEST_TRANSPORT_OK = "Real transport: received after %.1f s, payload intact"
L.SELFTEST_TRANSPORT_CORRUPT = "Real transport: received, but the payload differs"
L.SELFTEST_TRANSPORT_TIMEOUT = "Real transport: nothing received within %d s (see TESTING.md)"
L.SELFTEST_TRANSPORT_SKIPPED = "Real transport: skipped, addon messages are restricted right now (%s)"
L.SELFTEST_TRANSPORT_FAILED = "Real transport: the client refused to send (result: %s)"

-- Ticker --------------------------------------------------------------
L.UNKNOWN_PLACE = "somewhere"
L.DURING_BOSS = "During the boss: %s"
L.EARLIER = "Earlier: %s"
L.HELD_MORE = "... and %d more (see chat)"

L.TICKER = {
	death = {
		"{name} died.",
		"{name} has fallen. Press F.",
		"{name} discovered the floor.",
		"RIP {name}.",
	},
	death_again = {
		"{name} died. Again. ({count} today)",
		"{name} died again. The spirit healer knows them by name now.",
		"{name} is collecting deaths: {count} today.",
		"{name} died. Again. Death #{count}.",
	},
	drowned = {
		"{name} drowned. Water 1, {name} 0.",
		"{name} forgot to breathe.",
		"{name} is sleeping with the fishes.",
	},
	levelup = {
		"{name} reached level {level}!",
		"{name} dinged {level}. Grats!",
		"Level {level}! {name} is growing up.",
	},
	enter = {
		"{name} entered {instance}.",
		"{name} walked into {instance}. What could go wrong?",
	},
	leave = {
		"{name} left {instance}.",
		"{name} made it out of {instance}. Alive, apparently.",
	},
}

-- Stats ---------------------------------------------------------------
L.STATS_HEADER = "Stats:"
L.STATS_DEATH_KING = "Death King: %s (%d)"
L.STATS_NO_DEATHS = "Nobody died this session. Suspicious."
L.STATS_LINE = "  %s: %s"
L.STATS_DEATHS_SESSION = "Deaths this session"
L.STATS_DEATHS_ALLTIME = "Deaths all-time"
L.STATS_DROWNED_ALLTIME = "Drowned all-time"
L.STATS_LEVELUPS_SESSION = "Level-ups this session"
L.STATS_LEVELUPS_ALLTIME = "Level-ups all-time"
L.STATS_NONE = "-"
