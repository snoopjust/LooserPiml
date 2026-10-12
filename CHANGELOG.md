# Changelog

## v0.2.0 (unreleased)

Stats, leaderboard, settings and the LooserPiml friends list: friends
never need slash commands.

### Added

- **LooserPiml friends list**: LooserPiml now talks only to players on
  your LooserPiml friends list who added you too. Players without
  LooserPiml, or who aren't on your list, never receive anything from it,
  not even hidden addon messages. Add friends by name or with one click
  from your group, remove them per row: in the new **Friends** tab of the
  window or in Options › AddOns › LooserPiml › Friends. The list shows
  who is connected, who hasn't added you yet and who is offline. A one-time
  chat hint tells you when you're grouped but your list is empty.
  `/lp friends [add|remove|list]` for power users.

- **Minimap button** (left-click: window, right-click: settings, drag:
  move) with a tooltip showing friends online, deaths tonight and the
  Death King. Also listed in the Addon Compartment.
- **Group stats window** with the **Leaderboard**: Hall of Fame (Death
  King, Fish Food, Gold Hoarder, Speedrunner) and a ranking for deaths,
  gold looted, quests and level-ups, for tonight, this week or all time.
  Friends who are offline stay listed with their last known totals.
- **Settings** in Options › AddOns › LooserPiml: which Ticker messages
  to show (incl. boss recap and your own events), banner display time,
  size, sound and position (move/lock/reset), stats collection and
  sharing, reset my stats, minimap button, and a testing section (test
  mode, simulations, sample friends, self-test, debug log).
- **Stats recording** for your own character: deaths, level-ups (with
  played time per level), quests, every gold change with its source,
  rare-or-better loot, dungeon/raid/battleground visits, boss kills and
  wipes, crafting, gathering (herbs, ore, skinning, fishing), chests
  opened (counted, not shown yet), skill-ups, new zones, flights,
  hearthstone, jumps, food and drink, duels, battleground results, honor
  and time spent grouped with each friend. Stored on your computer; only
  totals are shared, and only with your LooserPiml friends (can be turned
  off).
- `/lp options` opens the settings; `/lp stats` opens the window
  (`/lp stats chat` prints the old text ranking).

### Changed

- **Communication**: no more messages to everyone in the group. In a group
  of only LooserPiml friends it is one group message as before; with
  anyone else in the group, each friend gets their own hidden whisper.
  Ticker events go to friends in your group, stats also to friends online
  elsewhere (on your WoW friends list). The version check runs only with
  your friends; nothing is sent to find out who else runs LooserPiml.
  Messages from players who aren't on your list are ignored.
- Nothing from test mode ever reaches real players, not even messages that
  were held during a simulated boss fight.
- `/lp selftest` tests the real transport only in a group where everyone
  is on your friends list, and never in test mode.

- Bigger, outlined banner text, colored per event; a sound for deaths and
  level-ups (`/lp sound on|off`).
- `/lp selftest` tests the real transport on the group channel instead of
  a whisper to yourself (the server rejects those); solo it only prints an
  info line.
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
