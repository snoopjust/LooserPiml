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
L.NAMES_SEPARATOR = ", "
L.NAMES_AND = " and "
L.CHAT_TAG = "|cff33ff99[LP]|r"
L.TEST_TAG = "|cff999999[test]|r"
L.ON = "on"
L.OFF = "off"

L.HELP_HEADER = "Commands:"
L.HELP_STATS = "open the LooserPiml window (\"/lp stats chat\": text ranking in chat)"
L.HELP_TEST = "test mode: messages loop back locally, fake friends appear"
L.HELP_SIM = "simulate an event (death, drown, levelup, enter, leave, boss, duel <name> ranked|fun|fled)"
L.HELP_SELFTEST = "check libraries, encoding and the real transport (with a connected friend)"
L.HELP_SOUND = "turn the banner sound on or off"
L.SOUND_STATE = "Banner sound: %s"
L.HELP_DEBUG ="debug logging, incl. blocked actions and Lua errors"
L.HELP_VERSION = "show your version and your LooserPiml friends' versions"
L.HELP_LOG = "print the recent debug log"
L.SLASH_UNKNOWN = "Unknown command '%s'."

L.DEBUG_STATE = "Debug mode: %s"
L.TEST_ON = "Test mode ON. Nothing is sent to other players; messages loop back locally. Fake friends: %s. Try /lp sim death Max"
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
L.OPT_TICKER_FRIENDS = "Ticker messages from friends"
L.OPT_TICKER_FRIENDS_TIP = "How your LooserPiml friends' events are shown, wherever they are playing. They are counted for the stats either way."
L.OPT_TICKER_FRIENDS_BANNER = "Banner"
L.OPT_TICKER_FRIENDS_CHAT = "Chat line only"
L.OPT_TICKER_FRIENDS_OFF = "Off"
L.OPT_SHOW_BOSS_RECAP = "Boss recap"
L.OPT_SHOW_BOSS_RECAP_TIP = "After a boss fight, show the banners that were held during the fight. Off: they only appear in chat."
L.OPT_SHOW_OWN = "Also show my own events"
L.OPT_DUEL_ASK = "Ask \"ranked?\" when dueling a LooserPiml friend"
L.OPT_DUEL_ASK_TIP = "Shows a small panel next to the game's duel dialog where you both pick Ranked or Just for fun. Off: your duels always count as just for fun."

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
L.OPT_STATS_SHARE = "Share my stats with my LooserPiml friends"
L.OPT_STATS_SHARE_TIP = "Send your totals (never the detailed log) to your connected LooserPiml friends, for the leaderboard."
L.OPT_STATS_RESET = "Reset my stats"
L.OPT_STATS_RESET_TIP = "Deletes this character's recorded stats. Friends keep the last totals you sent them."
L.OPT_STATS_RESET_CONFIRM = "Delete all recorded LooserPiml stats of this character?"
L.STATS_RESET_DONE = "Your stats were reset."

L.OPT_SECTION_MINIMAP = "Minimap"
L.OPT_MINIMAP_SHOW = "Show minimap button"

L.OPT_SECTION_TESTING = "Testing"
L.OPT_TEST_MODE = "Test mode"
L.OPT_TEST_MODE_TIP = "Nothing is sent to other players; fake friends appear. Off again after /reload."
L.OPT_TEST_SIM_DEATH = "Simulate a death"
L.OPT_TEST_SIM_LEVELUP = "Simulate a level up"
L.OPT_TEST_SIM_BOSS = "Simulate a boss fight"
L.OPT_TEST_SAMPLE_FRIENDS = "Fill with sample friends"
L.OPT_TEST_SAMPLE_FRIENDS_TIP = "Adds fake friends' stats so the leaderboard can be viewed solo (test mode only, never saved)."
L.OPT_TEST_SELFTEST = "Run self-test"
L.OPT_TEST_SHOW_LOG = "Show debug log"
L.SAMPLE_FRIENDS_DONE = "Sample friends added. Open the leaderboard with the minimap button."

-- LooserPiml friends ---------------------------------------------------
L.HELP_FRIENDS = "open your LooserPiml friends list (or: add <name>, remove <name>, list)"
L.FRIENDS_TITLE = "LooserPiml friends"
L.FRIENDS_HELP = "LooserPiml only talks to players on this list, and only once they have added you to their list too, whether you are grouped or not. Nobody else ever receives anything from LooserPiml. Add your friends here and ask them to add you."
L.FRIENDS_ADD_BY_NAME = "Add by name"
L.FRIENDS_ADD = "Add"
L.FRIENDS_REMOVE = "Remove"
L.FRIENDS_ADD_FROM_GROUP = "Add from group"
L.FRIENDS_ADD_FROM_WOW = "Add from WoW friends"
L.FRIENDS_NO_WOW_CANDIDATES = "Nobody on your WoW friends list who is not on this list."
L.FRIENDS_WOW_HINT = "Add each other on the WoW friends list too (Social > Friends): that is how LooserPiml sees that a friend is online when you are not grouped."
L.FRIENDS_NO_CANDIDATES = "Everyone in your group is on your list."
L.FRIENDS_NOT_IN_GROUP = "Not in a group."
L.FRIENDS_MORE_CANDIDATES = "%d more players are not shown: type their names instead."
L.FRIENDS_LIST_HEADER = "Your list (%d/%d)"
L.FRIENDS_EMPTY = "Nobody yet. Add your friends by name, from your group or from your WoW friends list."
L.FRIENDS_PAGE = "Page %d/%d"
L.FRIENDS_STATUS_CONNECTED = "connected"
L.FRIENDS_STATUS_WAITING = "online, waiting for them to add you"
L.FRIENDS_STATUS_OFFLINE = "offline (or not on your WoW friends list)"
L.FRIENDS_ADDED = "Added %s. Once they add you too, you share stats."
L.FRIENDS_REMOVED = "Removed %s. LooserPiml sends nothing to them any more."
L.FRIENDS_ERR_NAME = "That is not a character name. Use Name or Name-Realm."
L.FRIENDS_ERR_SELF = "That is you."
L.FRIENDS_ERR_LISTED = "%s is already on your list."
L.FRIENDS_ERR_FULL = "Your list is full (%d friends)."
L.FRIENDS_ERR_NOT_LISTED = "%s is not on your list."
L.FRIENDS_NONE = "Your LooserPiml friends list is empty."
L.FRIENDS_HINT_EMPTY = "Your LooserPiml friends list is empty, so LooserPiml shares nothing. Add your friends: minimap button > Friends."
L.OPT_SECTION_FRIENDS = "LooserPiml friends"
L.OPT_FRIENDS_MANAGE = "Friends list"
L.OPT_FRIENDS_MANAGE_BUTTON = "Manage"
L.OPT_FRIENDS_MANAGE_TIP = "LooserPiml only talks to players on this list who added you too."

-- Main window / minimap ----------------------------------------------
L.WINDOW_TITLE = "LooserPiml · Friends"
L.WINDOW_SETTINGS = "Settings"
L.WINDOW_VERSION = "Version %s"
L.WINDOW_UPDATE_AVAILABLE = "update available: %s"
L.WINDOW_OUTDATED = "outdated: %s"
L.WINDOW_ALL_CURRENT = "all friends on the latest version"
L.WINDOW_NO_FRIENDS_YET = "no LooserPiml friends online yet (see the Friends tab)"
L.TAB_LEADERBOARD = "Leaderboard"
L.TAB_FRIENDS = "Friends"
L.TOOLTIP_LEFT_CLICK = "Left-click: open/close the window"
L.TOOLTIP_RIGHT_CLICK = "Right-click: settings"
L.TOOLTIP_FRIENDS_ONLINE = "Friends online with LooserPiml: %d"
L.TOOLTIP_TONIGHT_DEATHS = "Deaths tonight: %d"
L.TOOLTIP_DEATH_KING = "Death King: %s (%d)"
L.TOOLTIP_DEATH_KING_NONE = "Death King: no one yet"

-- Leaderboard ---------------------------------------------------------
L.LEADERBOARD_SUBTITLE = "Everyone compared: who is best (or worst) at what"
L.LEADERBOARD_EMPTY = "Add your friends in the Friends tab (and ask them to add you) to compare your stats."
L.PERIOD_TONIGHT = "Tonight"
L.PERIOD_WEEK = "This week"
L.PERIOD_ALL = "All time"
L.HALL_OF_FAME = "Hall of Fame"
L.RANKING = "Ranking"
L.METRIC_DEATHS = "Deaths"
L.METRIC_GOLD = "Gold"
L.RIGHT_NOW = "%s right now"
L.GOLD_RIGHT_NOW_NOTE = "gold on hand right now (the period does not apply)"
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
L.VERSION_NONE = "  No LooserPiml friends on your list yet."
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
L.SELFTEST_TRANSPORT_SENT = "Real transport: sent %d bytes (%d chunks) to %s, waiting up to %d s for the echo ..."
L.SELFTEST_TRANSPORT_OK = "Real transport: echo from %s received after %.1f s, payload intact"
L.SELFTEST_TRANSPORT_CORRUPT = "Real transport: received, but the payload differs"
L.SELFTEST_TRANSPORT_TIMEOUT = "Real transport: nothing received within %d s (see TESTING.md)"
L.SELFTEST_TRANSPORT_SKIPPED = "Real transport: skipped, addon messages are restricted right now (%s)"
L.SELFTEST_TRANSPORT_FAILED = "Real transport: the client refused to send (result: %s)"
L.SELFTEST_TRANSPORT_TESTMODE = "Real transport: not tested in test mode (nothing leaves your client). Turn test mode off and run it again."
L.SELFTEST_TRANSPORT_NO_FRIEND = "Real transport: not tested, no LooserPiml friend is connected right now (the server rejects whispers to yourself). Run it again while a friend shows \"connected\"."

-- Ticker --------------------------------------------------------------
L.UNKNOWN_PLACE = "somewhere"
L.DURING_BOSS = "During the boss: %s"
L.EARLIER = "Earlier: %s"
L.HELD_MORE = "... and %d more (see chat)"

L.TICKER = {
	wishloot = {
		"{name} looted {item} ×{count} · On {owner} · {need}",
	},
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

-- Friends' inventory ----------------------------------------------------
L.OPT_SECTION_INVENTORY = "Inventory"
L.OPT_SHARE_INVENTORY = "Share my bags and bank with my LooserPiml friends"
L.OPT_SHARE_INVENTORY_TIP = "Your friends see what you carry and what was in your bank when you last opened it. Equipped items are never shared. Off: nothing is sent and your friends drop what they had."
L.OPT_SHARE_GOLD = "Share my gold with my LooserPiml friends"
L.OPT_SHARE_GOLD_TIP = "Your gold on hand right now, for the gold bar, Gold Hoarder and the Gold ranking. Off: you are left out of all three, also on your own screen."
L.ITEM_LOADING = "Loading ..."
L.TAB_INVENTORY = "Inventory"
L.INV_TITLE = "Friends' inventory"
L.INV_SUBTITLE = "Bags and banks of your LooserPiml friends, updated automatically"
L.INV_VIEW_ITEMS = "Items"
L.INV_VIEW_WISHLIST = "Wishlists"
L.INV_SEARCH_HINT = "Search items ..."
L.INV_FILTER_ALL = "All"
L.INV_FILTER_MATERIALS = "Materials"
L.INV_FILTER_CONSUMABLES = "Consumables"
L.INV_FILTER_GEAR = "Gear"
L.INV_FILTER_BAGS_BANK = "Bags + bank"
L.INV_FILTER_BAGS = "Bags"
L.INV_FILTER_BANK = "Bank"
L.INV_COUNT = "%d items held by %d friends"
L.INV_GOLD_TOTAL = "Total %s"
L.INV_BANK_TAG = "bank"
L.INV_MORE_HOLDERS = "+%d more"
L.INV_EMPTY = "Nothing to show yet. Your friends' bags appear here once you are connected."
L.INV_EMPTY_SEARCH = "None of your friends has this yet. Add it to your wishlist and you'll get a heads-up when someone loots it."
L.INV_PAGE = "Page %d/%d"
L.INV_LAST_UPDATED = "Last updated"
L.INV_UPDATED_ONLINE = "bags now · bank %s"
L.INV_UPDATED_OFFLINE = "offline · last seen %s"
L.INV_UPDATED_NOT_SHARED = "doesn't share bags"
L.INV_NEVER = "never seen"
L.INV_NO_FRIENDS = "No LooserPiml friends connected yet."
L.INV_BANK_NOTE = "Banks update when their owner opens the bank."
L.WISH_ADD_BUTTON = "+ Add to my wishlist"
L.AGO_NOW = "now"
L.AGO_MINUTES = "%d min ago"
L.AGO_HOURS = "%d h ago"
L.AGO_YESTERDAY = "yesterday"
L.AGO_DAYS = "%d days ago"
L.WHEN_TODAY = "today %s"
L.WHEN_YESTERDAY = "yesterday %s"
L.OPT_SHOW_WISHLIST = "Banner when a wishlist item is looted"
L.OPT_SHOW_WISHLIST_TIP = "When a LooserPiml friend loots something that is on a wishlist (yours or a friend's). Follows \"Ticker messages from friends\" too."
L.WISH_OWNER = "%s's wishlist"
L.WISH_OWNER_YOU = "your wishlist"
L.WISH_STILL_NEEDED = "%d still needed"
L.WISH_ENOUGH = "enough now"
L.SIM_WISH_ITEM = "Medium Leather"
L.SIM_WISH_OWNER = "Lena"
L.WISH_ADD_LABEL = "My wishlist"
L.WISH_INPUT_HINT = "Type an item name or shift-click an item, then the quantity."
L.WISH_NOTE = "Everyone adds only their own wishes; all friends can see them."
L.WISH_ADDED = "Added to your wishlist."
L.WISH_REMOVE = "Remove"
L.WISH_EMPTY = "No wishes yet. Add what you are looking for, and your friends see it."
L.WISH_ERR_UNKNOWN = "Unknown item. Shift-click it, or type its exact name (the item has to be known to your client)."
L.WISH_ERR_QUANTITY = "The quantity must be a number from 1 to 10000."
L.WISH_ERR_FULL = "Your wishlist is full (%d items)."
L.WISH_FOR = "for %s"
L.WISH_FOR_YOU = "for you"
L.WISH_AMONG_FRIENDS = "%d among friends"
L.WISH_LOOTED_TONIGHT = "%d looted tonight"
L.WISH_NOBODY_HAS = "no friend has it yet"

-- Profiles ----------------------------------------------------------------
L.TAB_PROFILES = "Profiles"
L.PROFILE_SUBTITLE = "One player in depth: everything LooserPiml has recorded"
L.PROFILE_LEVEL_SHORT = "Lv %d"
L.PROFILE_PROGRESS = "Progress"
L.PROFILE_LEVEL = "Level"
L.PROFILE_PLAYED = "Time played"
L.PROFILE_AVG_LEVEL = "Avg time per level"
L.PROFILE_QUESTS = "Quests"
L.PROFILE_DEATHS = "Deaths"
L.PROFILE_DEATHS_TOTAL = "Total"
L.PROFILE_DROWNED = "Drowned"
L.PROFILE_BOSS_DEATHS = "During boss fights"
L.PROFILE_FIRST_DEATHS = "First to die in a dungeon"
L.PROFILE_LOOT = "Loot & gold"
L.PROFILE_GOLD = "Gold on hand"
L.PROFILE_EARNED_AH = "Earned at the auction house"
L.PROFILE_EARNED_VENDOR = "Earned at vendors"
L.PROFILE_REPAIRS = "Spent on repairs"
L.PROFILE_RARE_EPIC = "Rare / epic items"
L.PROFILE_PROFESSIONS = "Professions"
L.PROFILE_PROFESSION_LIST = "Professions"
L.PROFILE_SKILLUPS = "Skill-ups"
L.PROFILE_CRAFTED = "Items crafted"
L.PROFILE_GATHERED = "Nodes gathered"
L.PROFILE_TRAVEL = "Travel"
L.PROFILE_ZONES = "Zones discovered"
L.PROFILE_FLIGHTS = "Flights"
L.PROFILE_HEARTHS = "Hearthstone uses"
L.PROFILE_FAV_ZONE = "Favourite zone"
L.PROFILE_PVP = "PvP"
L.PROFILE_RANK = "Rank"
L.PROFILE_BG_WON = "Battlegrounds won"
L.PROFILE_DUELS = "Duels won / lost"
L.PROFILE_SOCIAL = "Social"
L.PROFILE_JUMPS = "Jumps"
L.PROFILE_FOOD = "Food eaten"
L.PROFILE_GROUPED = "Time grouped with friends"
L.PROFILE_EVENINGS = "Evenings played"

-- Ranked duels ------------------------------------------------------------------
L.DUEL_PANEL_TITLE = "LooserPiml · ranked duel?"
L.DUEL_RECORD = "Your ranked record against %s: %d – %d"
L.DUEL_RANKED = "Ranked"
L.DUEL_FUN = "Just for fun"
L.DUEL_NOTE = "Counts as ranked only if both pick Ranked. You still accept or decline in the game's dialog: LooserPiml never does that for you."
L.DUEL_STATUS_NONE = "Nobody picked yet."
L.DUEL_STATUS_WAITING = "You picked Ranked · waiting for %s…"
L.DUEL_STATUS_BOTH_RANKED = "You both picked Ranked: this duel counts!"
L.DUEL_STATUS_MINE_FUN = "You picked Just for fun · this duel doesn't count for the ladder."
L.DUEL_STATUS_THEIRS_FUN = "%s picked Just for fun · this duel doesn't count for the ladder."
L.DUEL_STATUS_THEY_RANKED = "%s picked Ranked · your turn."
L.DUEL_STATUS_OFF = "%s doesn't ask for ranked duels · just for fun."

-- Tonight ---------------------------------------------------------------------
L.TAB_TONIGHT = "Tonight"
L.TONIGHT_RECAP_TITLE = "Tonight's awards"
L.TONIGHT_RECAP_EMPTY = "No awards yet tonight. Go die somewhere."
L.TONIGHT_TIMELINE = "Timeline"
L.TONIGHT_EMPTY = "Nothing happened yet tonight (since 06:00)."
L.KPI_SESSION = "Session"
L.KPI_DEATHS = "Deaths"
L.KPI_LEVELUPS = "Level-ups"
L.KPI_LOOTED = "Gold looted"
L.KPI_DUELS = "Duels"
L.RECAP_MOST_LEVELUPS = "Most level-ups"
L.RECAP_MOST_QUESTS = "Most quests"
L.RECAP_MOST_LOOTED = "Most gold looted"
L.RECAP_TITLE = "Last evening (%s)"
L.RECAP_LINE = "%s: %s (%s)"
L.RECAP_TOTALS = "Deaths %d · Level-ups %d · Gold looted %s · Duels %d"
L.OPT_SHOW_RECAP = "Show evening recap"
L.OPT_SHOW_RECAP_TIP = "On the first login after 06:00, a small window with last evening's awards and totals (only on your screen)."
