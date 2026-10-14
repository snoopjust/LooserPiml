# Changelog

## Unreleased

- **Gold Hoarder** now goes to the friend with the most gold on hand right
  now (not gold looted). The ranking metric "Gold looted" became **Gold**:
  current gold, highest first, marked "right now"; the period selector
  doesn't apply to it. New setting **Share my gold** (Settings › Stats, on
  by default): friends who turn it off are left out of both. Gold by
  source is still recorded in the background.
- The own character is never offered or listed as a LooserPiml friend.

## v0.2.0-beta.1 (2026-10-12, pre-release)

First beta of v0.2.0, for the first test with a friend. Stats, leaderboard,
settings and the LooserPiml friends list: friends never need slash
commands. Everything works between friends whether you play together or
each on your own.

### Added

- **LooserPiml friends list**: LooserPiml talks only to players on your
  LooserPiml friends list who added you too. Players without LooserPiml,
  or who aren't on your list, never receive anything from it, not even
  hidden addon messages. Add friends by name, with one click from your
  group or from your WoW friends list, remove them per row: in the
  **Friends** tab of the window or in Options › AddOns › LooserPiml ›
  Friends. The list shows who is connected, who hasn't added you yet and
  who is offline. Add each other on the WoW friends list too, so
  LooserPiml can see when a friend is online. A chat hint after login
  tells you when your list is still empty. `/lp friends [add|remove|list]`
  for power users.
- **Minimap button** (left-click: window, right-click: settings, drag:
  move) with a tooltip showing friends online, deaths tonight and the
  Death King. Also listed in the Addon Compartment.
- **Window "LooserPiml · Friends"** with the **Leaderboard**: Hall of Fame
  (Death King, Fish Food, Gold Hoarder, Speedrunner) and a ranking for
  deaths, gold looted, quests and level-ups, for tonight, this week or all
  time.
  Friends who are offline stay listed with their last known totals.
- **Settings** in Options › AddOns › LooserPiml: your friends list,
  "Ticker messages from friends" (Banner / Chat line only / Off), which
  Ticker messages to show (incl. boss recap and your own events), banner
  display time, size, sound and position (move/lock/reset), stats
  collection and sharing, reset my stats, minimap button, and a testing
  section (test mode, simulations, sample friends, self-test, debug log).
- **Stats recording** for your own character: deaths, level-ups (with
  played time per level), quests, every gold change with its source,
  rare-or-better loot, dungeon/raid/battleground visits, boss kills and
  wipes, crafting, gathering (herbs, ore, skinning, fishing), chests
  opened (counted, not shown yet), skill-ups, new zones, flights,
  hearthstone, jumps, food and drink, duels, battleground results, honor
  and time spent grouped with each friend. Stored on your computer; only
  totals are shared, and only with your LooserPiml friends (can be turned
  off).
- Friends entering or leaving the same dungeon together get one banner:
  "Max and Lootius entered The Deadmines."
- `/lp options` opens the settings; `/lp stats` opens the window
  (`/lp stats chat` prints the old text ranking).

### Changed

- **Communication**: LooserPiml no longer sends anything to your party or
  raid. Every message is a hidden whisper to each connected LooserPiml
  friend, wherever they are: Ticker events (deaths, level-ups, dungeons)
  and stats reach your friends whether you are grouped or not. The
  version check runs only with your friends; nothing is sent to find out
  who else runs LooserPiml. Messages from players who aren't on your list
  are ignored.
- `/lp selftest` tests the real transport with a connected friend, whose
  LooserPiml sends the test message back; never in test mode.
- Nothing from test mode ever reaches real players, not even messages that
  were held during a simulated boss fight.
- Bigger, outlined banner text, colored per event; a sound for deaths and
  level-ups (`/lp sound on|off`).
- Saved settings are migrated automatically (banner settings grouped).
  Stats received from other players before the friends list existed are
  dropped; nobody had agreed to share them.

## v0.1.0 (2026-10-11)

First version: Core + Ticker MVP for WoW: Forever (beta, Interface 16001).
Not yet verified in-game; see TESTING.md.

### Added

- Ticker: banner + chat line when someone in your group levels up, dies
  (with a "drowned" variant) or enters/leaves a dungeon or raid. Several fun
  variants per event; "Again" variants count deaths per session.
- Events during a boss encounter are held and shown afterwards
  ("During the boss: …").
- `/lp stats`: Death King and rankings (session + all-time).
- Version check: tells you locally when someone in the group runs an older
  or newer LooserPiml.
- Test mode (`/lp test on`), simulations (`/lp sim …`), `/lp selftest`,
  `/lp debug`, `/lp log`, `/lp version`.
