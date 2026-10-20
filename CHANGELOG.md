# Changelog

## Unreleased

### Fixed

- `/lp sim duel` waits for your pick before the simulated duel starts
  (it used to close the panel after 8 s, so a late click didn't count).
- Ranked duel panel: no more empty gap above the status line.
- PvP tab: the "W – L" column sits right after the last player instead of
  at the far right.
- Settings: "Ask "ranked?" in duels" (the longer label was cut off).

## v0.2.0-beta.3 (2026-10-19, pre-release)

Third beta: ranked duels, for the duel test with a friend this weekend.

### Added

- **Ranked duels** between LooserPiml friends, grouped or not. When you
  duel a connected LooserPiml friend, a small panel "LooserPiml · ranked
  duel?" appears below the game's duel dialog on both sides, with your
  ranked record against them and two buttons: **Ranked** and **Just for
  fun**. The duel counts as ranked only if both pick Ranked. You still
  accept or decline in the game's own dialog: LooserPiml never does that
  for you. With anyone else there is no panel and the duel is a normal
  one. Fleeing counts as a loss.
- **PvP** (new tab): the duel ladder (ranked only: wins, losses, win rate,
  streak like W4 / L2) and a head to head matrix (who beat whom how often,
  Ranked or All duels, W – L per player). Battlegrounds come later.
  A ranked duel counts once both duelists' clients agree on the result;
  if they don't, it's marked disputed and left out.
- Banner after a ranked duel for all your connected friends: "Lootius won
  a ranked duel against Nerdalot · Ranked head to head: Lootius 5 – 1
  Nerdalot". Fun duels can show a chat line instead.
- Hall of Fame: **Duel King** (most ranked duel wins in the period).
- Profiles › PvP: "Ranked duels won / lost" and "All duels won / lost".
- Settings › Ticker messages: "Ranked duel results" (banner, on), "Fun
  duel results" (chat line, off), "Ask "ranked?" when dueling a
  LooserPiml friend" (on).
- Test mode: `/lp sim duel <name> ranked|fun|fled`.

## v0.2.0-beta.2 (2026-10-14, pre-release)

Second beta, for the test with a friend before the Forever beta ends.

### Added

- **Friends' inventory** (new tab "Inventory"): what your LooserPiml
  friends carry in their bags and keep in their bank, plus their gold on
  hand. Gold bar with a chip per friend and a total, search by item name
  as you type, filters (All / Materials / Consumables / Gear, Bags + bank /
  Bags / Bank), one row per item with who has how many (and whether it's
  in the bank), and when each friend's bags and bank were last updated.
  Banks update when their owner opens the bank. Equipped items are never
  shared.
- **Wishlists**: add what you're looking for (type the name or shift-click
  the item, plus a quantity). Everyone adds only their own wishes; all
  friends see them, with how many your friends already have. When a friend
  loots something on a wishlist you get a banner: "Pew looted Medium
  Leather ×3 · On Justice Beaver's wishlist · 7 still needed".
- **Profiles** (new tab): one player in depth: progress, deaths, loot and
  gold, professions, travel, PvP and social stats; "—" where there's no
  data yet.
- **Tonight** (new tab): tonight's awards, totals (session, deaths,
  level-ups, gold looted, duels) and a timeline of everything that
  happened to you and your friends since 06:00. On the first login of a
  new day a small window shows last evening's recap (can be turned off).
- Settings › Inventory: "Share my bags and bank with my LooserPiml
  friends", "Share my gold with my LooserPiml friends" (moved here),
  "Banner when a wishlist item is looted". Settings › Stats: "Show
  evening recap".

### Changed

- **Gold Hoarder** goes to the friend with the most gold on hand right now
  (not gold looted). The ranking metric "Gold looted" became **Gold**:
  current gold, highest first, shown as "71g 60s right now"; the period
  selector doesn't apply to it. Friends who don't share gold are left
  out. Gold by source is still recorded in the background.
- Played time and time grouped are counted quietly instead of triggering
  a stats message every minute.

### Fixed

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
