# Changelog

## v0.2.0 (unreleased)

Stats, leaderboard and settings: friends never need slash commands.

### Added

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
  wipes, crafting, gathering, skill-ups, new zones, flights, hearthstone,
  jumps, food and drink, duels, battleground results, honor and time
  spent grouped with each friend. Stored on your computer; only totals are
  shared with your group (can be turned off).
- `/lp options` opens the settings; `/lp stats` opens the window
  (`/lp stats chat` prints the old text ranking).

### Changed

- Bigger, outlined banner text, colored per event; a sound for deaths and
  level-ups (`/lp sound on|off`).
- `/lp selftest` tests the real transport on the group channel instead of
  a whisper to yourself (the server rejects those); solo it only prints an
  info line.
- Saved settings are migrated automatically (banner settings grouped).

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
