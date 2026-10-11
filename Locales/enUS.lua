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
L.ADDON_NAME = "LooserPiml"
L.ADDON_PREFIX = "|cff33ff99LooserPiml|r"
L.CHAT_TAG = "|cff33ff99[LP]|r"
L.TEST_TAG = "|cff999999[test]|r"
L.ON = "on"
L.OFF = "off"

L.HELP_HEADER = "Commands:"
L.HELP_STATS = "open the group stats window (\"/lp stats chat\": text ranking in chat)"
L.HELP_TEST = "test mode: messages loop back locally, fake group members"
L.HELP_SIM = "simulate an event (death, drown, levelup, enter, leave, boss)"
L.HELP_SELFTEST = "check libraries, encoding and the real addon-message transport"
L.HELP_SOUND = "turn the banner sound on or off"
L.SOUND_STATE = "Banner sound: %s"
L.HELP_DEBUG ="debug logging, incl. blocked actions and Lua errors"
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

-- Options (Options > AddOns > LooserPiml) ------------------------------
L.HELP_OPTIONS = "open the settings (Options > AddOns > LooserPiml)"
L.OPTIONS_UNAVAILABLE = "The settings panel is not available on this client."
L.OPT_RESET_BUTTON = "Reset"
L.OPT_RUN_BUTTON = "Run"

L.OPT_SECTION_TICKER = "Ticker messages"
L.OPT_SHOW_LEVELUP = "Level ups"
L.OPT_SHOW_DEATH = "Deaths"
L.OPT_SHOW_DROWNED = "Drownings"
L.OPT_SHOW_DUNGEON = "Dungeon enter/leave"
L.OPT_SHOW_RAID = "Raid enter/leave"
L.OPT_SHOW_BOSS_RECAP = "Boss recap"
L.OPT_SHOW_BOSS_RECAP_TIP = "After a boss fight, show the banners that were held during the fight. Off: they only appear in chat."
L.OPT_SHOW_OWN = "Also show my own events"

L.OPT_SECTION_BANNER = "Banner"
L.OPT_BANNER_HOLD = "Display time"
L.OPT_BANNER_SIZE = "Text size"
L.OPT_BANNER_SOUND = "Sound for deaths and level ups"
L.OPT_BANNER_MOVE = "Move banner"
L.OPT_BANNER_MOVE_BUTTON = "Unlock / lock"
L.OPT_BANNER_MOVE_TIP = "Shows a sample banner you can drag with the left mouse button. Click again to lock it."
L.OPT_BANNER_RESET = "Reset banner position"
L.BANNER_MOVE_HINT = "LooserPiml banner - drag me, then lock it in the settings"
L.BANNER_UNLOCKED = "Banner unlocked: drag it, then click \"Unlock / lock\" again."
L.BANNER_LOCKED = "Banner locked."

L.OPT_SECTION_STATS = "Stats"
L.OPT_STATS_COLLECT = "Collect stats"
L.OPT_STATS_COLLECT_TIP = "Record deaths, gold, quests, loot and more for your character (stored on your computer only)."
L.OPT_STATS_SHARE = "Share my stats with the group"
L.OPT_STATS_SHARE_TIP = "Send your totals (never the detailed log) to group members who use LooserPiml, for the leaderboard."
L.OPT_STATS_RESET = "Reset my stats"
L.OPT_STATS_RESET_TIP = "Deletes this character's recorded stats. Friends keep the last totals you sent them."
L.OPT_STATS_RESET_CONFIRM = "Delete all recorded LooserPiml stats of this character?"
L.STATS_RESET_DONE = "Your stats were reset."

L.OPT_SECTION_MINIMAP = "Minimap"
L.OPT_MINIMAP_SHOW = "Show minimap button"

L.OPT_SECTION_TESTING = "Testing"
L.OPT_TEST_MODE = "Test mode"
L.OPT_TEST_MODE_TIP = "Nothing is sent to other players; fake group members appear. Off again after /reload."
L.OPT_TEST_SIM_DEATH = "Simulate a death"
L.OPT_TEST_SIM_LEVELUP = "Simulate a level up"
L.OPT_TEST_SIM_BOSS = "Simulate a boss fight"
L.OPT_TEST_SAMPLE_FRIENDS = "Fill with sample friends"
L.OPT_TEST_SAMPLE_FRIENDS_TIP = "Adds fake friends' stats so the leaderboard can be viewed solo (test mode only, never saved)."
L.OPT_TEST_SELFTEST = "Run self-test"
L.OPT_TEST_SHOW_LOG = "Show debug log"
L.SAMPLE_FRIENDS_DONE = "Sample friends added. Open the leaderboard with the minimap button."

-- Main window / minimap ----------------------------------------------
L.WINDOW_TITLE = "LooserPiml · Group stats"
L.WINDOW_SETTINGS = "Settings"
L.WINDOW_VERSION = "Version %s"
L.WINDOW_UPDATE_AVAILABLE = "update available: %s"
L.WINDOW_OUTDATED = "outdated: %s"
L.WINDOW_ALL_CURRENT = "all friends on the latest version"
L.WINDOW_NO_FRIENDS_YET = "no friends seen this session"
L.TAB_LEADERBOARD = "Leaderboard"
L.TOOLTIP_LEFT_CLICK = "Left-click: open/close the window"
L.TOOLTIP_RIGHT_CLICK = "Right-click: settings"
L.TOOLTIP_FRIENDS_ONLINE = "Friends online with LooserPiml: %d"
L.TOOLTIP_TONIGHT_DEATHS = "Deaths tonight: %d"
L.TOOLTIP_DEATH_KING = "Death King: %s (%d)"
L.TOOLTIP_DEATH_KING_NONE = "Death King: no one yet"

-- Leaderboard ---------------------------------------------------------
L.LEADERBOARD_SUBTITLE = "Everyone compared: who is best (or worst) at what"
L.LEADERBOARD_EMPTY = "Group up with friends who use LooserPiml to compare your stats."
L.PERIOD_TONIGHT = "Tonight"
L.PERIOD_WEEK = "This week"
L.PERIOD_ALL = "All time"
L.HALL_OF_FAME = "Hall of Fame"
L.RANKING = "Ranking"
L.METRIC_DEATHS = "Deaths"
L.METRIC_GOLD = "Gold looted"
L.METRIC_QUESTS = "Quests"
L.METRIC_LEVELUPS = "Level-ups"
L.AWARD_DEATH_KING = "Death King"
L.AWARD_FISH_FOOD = "Fish Food"
L.AWARD_GOLD_HOARDER = "Gold Hoarder"
L.AWARD_SPEEDRUNNER = "Speedrunner"
L.NO_ONE_YET = "No one yet"
L.YOU_SUFFIX = "(you)"
L.OFFLINE_SUFFIX = "(offline)"

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
L.SELFTEST_TRANSPORT_SENT = "Real transport: sent %d bytes (%d chunks) to your group, waiting up to %d s for the echo ..."
L.SELFTEST_TRANSPORT_SOLO = "Real transport: not tested, you are not in a group (the server rejects whispers to yourself). Join a group and run /lp selftest again."
L.SELFTEST_TRANSPORT_OK = "Real transport: echo received after %.1f s, payload intact"
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
