# Status

_Last updated: 2026-10-12 (stage A: stats foundation, minimap button, leaderboard, settings; not yet tested in-game, not released)_

## Done

- **Core**, reusable by later modules:
  - `Core/Init.lua`: namespace, core-service registry, module registry (enable/disable at runtime, persisted toggle), lifecycle (ADDON_LOADED → PLAYER_LOGIN), `ns.SafeCall` error isolation, `ns.IsSecret`.
  - `Core/Events.lua`: central dispatcher (owners, method or function handlers, internal `LP_*` messages, skips events the client doesn't know), boss-encounter state with a lost-event safety net and test-mode simulation.
  - `Core/DB.lua`: `LooserPimlDB` with `schemaVersion` and ordered migrations, defaults, per-module storage.
  - `Core/Log.lua`: ring buffer, debug output, capture of `ADDON_ACTION_BLOCKED`/`FORBIDDEN`/`LUA_WARNING` and our Lua errors (error-handler hook only in debug/test mode).
  - `Core/Roster.lua`: group members as `Name-Realm`, class colors, channel choice (RAID/PARTY/INSTANCE_CHAT), fake members.
  - `Core/Comm.lua`: AceComm prefix `LPiml`, AceSerializer + LibDeflate, protocol versioning, hold queue during restrictions, retry of refused sends, duplicate filter, test loopback, self-test transport.
  - `Core/Version.lua`: HELLO handshake (login, joins, coalesced, replies), local warnings for older/newer/incompatible versions.
  - `Core/TestMode.lua`: loopback, fake group (incl. outdated version), simulation registry, `/lp sim boss`, `/lp selftest`.
  - `Core/Slash.lua`: `/lp` and `/looserpiml` with a registry for module subcommands.
  - `Core/PlayerEvents.lua` (stage A): detection of the own player's death (incl. drowned), level-up, instance enter/leave, shared by Ticker and Stats via `LP_*` messages.
  - `Core/Util.lua` (stage A): localized GlobalStrings matching, money/duration formatting.
  - `Core/Options.lua` (stage A): settings registry + Blizzard Settings panel, confirmation dialogs.
  - `Core/Window.lua` (stage A): main window shell with tab registry, minimap button (LibDataBroker + LibDBIcon), Addon Compartment entry, footer version status.
- **Ticker module**: level up, death (+ drowned), dungeon/raid enter/leave. Each client detects only its own events, shows them locally and broadcasts them. Center banner (queue, fade, class colors, configurable time/size/position, sound) + local chat line. Held during encounters and shown afterwards ("During the boss: …"). Per-type display filters. Session counters for the banner text; `/lp stats chat` prints the old text ranking.
- **Stats module** (stage A): per-character event log (death, level-up with played time, quests, gold with source, rare loot, instances, boss kills/wipes, crafting/gathering/skill-ups, travel, duels, battlegrounds, honor) plus live counters (jumps, food/drink, group time per friend); rollup into daily buckets (30 days / 5000 events); aggregates per tonight / this week / all time; sharing of aggregates with friends (≤ 1 per 30 s, share setting), friends cache with last seen; Leaderboard tab with Hall of Fame (Death King, Fish Food, Gold Hoarder, Speedrunner) and ranking (deaths, gold looted, quests, level-ups).
- **Tests**: 156 busted specs, all green, running the real addon + real libraries (incl. LibDBIcon) under Lua 5.1, including two clients talking to each other.
- **Tooling**: `tools/fetch-libs.ps1`, `tools/link-addon.ps1` (junction created: `<WoW>\_classic_beta_\Interface\AddOns\LooserPiml` → repo), `tools/setup-test-env.ps1`, `tools/run-tests.ps1`.
- **Distribution**: `.pkgmeta` (libs as git externals, pinned), GitHub Actions `tests.yml` (push/PR) and `release.yml` (tag `v*` → tests → BigWigsMods/packager → GitHub release + `release.json`).
- **Published** (2026-10-11): public repo https://github.com/snoopjust/LooserPiml. Release **v0.1.0** built by CI (tests 78/78 green on Ubuntu, packager job green): `LooserPiml-v0.1.0-forever.zip` with all libraries embedded, `## Version: v0.1.0`, no dev files; `release.json` flavor `forever`, interface 16001. Known cosmetic issue: LibDeflate's docs/examples (~170 KB) are included in the zip.
- **Docs**: README (friends' install via WowUp + manual), ARCHITECTURE.md (files, load order, end-to-end event diagram, restriction handling), CLAUDE.md (conventions), TESTING.md (solo + two-client checklists, all `TODO(verify in-game)` items), CHANGELOG.

## Safety rules

Every feature is checked against these:

1. Official in-game Lua/XML API only. No external tools, no client modification, no memory reading.
2. Secret/protected values are never circumvented, derived or reconstructed. Every comparison or arithmetic on API data is preceded by `ns.IsSecret`; if secret, the value is dropped and the feature degrades (e.g. no "drowned" variant, unknown class → uncolored name, unknown encounter state → treated as restricted).
3. No visible chat output to anyone. Sync is hidden addon messages via AceComm only. Display is local (own frame, `DEFAULT_CHAT_FRAME:AddMessage`). The test mock errors on any `SendChatMessage`.
4. No automation of game actions.
5. All traffic through ChatThrottleLib. Messages only on real events; HELLO coalesced (10 s cooldown); held queue capped (50), retries every 5 s with at most 5 attempts.
6. Plain readable code, free, no ads, no donation requests.
7. Debug/test mode shows blocked/forbidden actions and Lua errors immediately.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Repo location | Local working folder chosen by the developer. Repo root = addon folder | As requested |
| Client folder | `<WoW>\_classic_beta_` | Has `WowB.exe`, flavor `wow_classic_beta`; addon guides confirm it is the Forever beta |
| TOC | One `LooserPiml.toc`, `## Interface: 16001` | Warcraft Wiki TOC table lists 16001 for Forever beta; the packager maps `16xxx` → game type `forever` |
| Libraries | Ace3 **Release-r1403** (2026-08-12: AceComm r14, ChatThrottleLib v32), LibDeflate **1.0.2-release**, LibDataBroker **v1.1.4** (GitHub) and LibDBIcon **v12.1.1** (WoWAce SVN), pinned in `.pkgmeta` and `fetch-libs.ps1` | Reproducible builds. LibDBIcon only exists in SVN; the packager installs svn by itself, local dev fetches the two files over HTTPS |
| Prefix / protocol | `LPiml`, protocol 1, envelope `{v,t,s,id,d,late}` | Short, under 16 chars; `s` (random session id) keeps ids unique across /reload |
| Own events | Shown locally right away; group-channel echoes ignored | Works solo and during restrictions; no double banners |
| Restriction handling | Hold if an encounter is active (our ENCOUNTER_START/END tracking or `C_InstanceEncounter.IsEncounterInProgress`) or `C_ChatInfo.InChatMessagingLockdown()`. Also hold and retry when AceComm reports `didSend == false`. Flush on `LP_ENCOUNTER_END`, `ADDON_RESTRICTION_STATE_CHANGED` (Inactive), `PLAYER_ENTERING_WORLD`, and a 5 s retry ticker | Covers the documented APIs plus the actual result codes, without relying on one signal |
| "Late" marker | Messages held for an encounter carry `late = "encounter"`, so receivers show "During the boss: …". Other lockdowns carry `"lockdown"` and show "Earlier: …" | Receivers otherwise can't tell old news from new |
| Banners during encounters | Held (own too), max 5 shown afterwards + "… and N more", with a 2 s watcher in case no end event arrives | Don't distract mid-fight |
| Channel | INSTANCE_CHAT in finder groups, else RAID, else PARTY | Standard practice; INSTANCE_CHAT is a TODO(verify) |
| Test mode | Not saved (off after /reload). Sims only in test mode. Test events never touch all-time stats | Avoid "why does nothing reach my friend" and fake stats |
| Dev builds | `@project-version@` → "dev", never compared, except in test mode, where dev = 1.0.0 so the warnings can be tried solo | Dev checkout playing with friends must not spam warnings |
| Icons | Raid target textures instead of emoji | WoW fonts have no emoji glyphs |
| Drowning | Drowned if the BREATH timer was draining and ≤ 1000 ms were left at death, or it stopped ≤ 1.5 s before death with ≤ 1000 ms left. Uses `GetMirrorTimerProgress` when > 0, else the START payload | No combat log needed (CLEU is unavailable in Midnight/Forever) |
| Corpse runs | No "left" while dead/ghost; re-entering the same instance within 10 min is quiet | Avoids enter/leave spam on wipes |
| Raids | Count as instances for enter/leave (confirmed 2026-10-11) | Wanted by the group; same code path as dungeons |
| Language | English only for now; strings stay in `Locales/enUS.lua` so a translation can be added later | Decided 2026-10-11 |
| Git identity / privacy | Commits use the GitHub noreply address (`git config --local user.email`); history rewritten before the first push so no commit contains the private email or machine-specific paths (drive letters, usernames) | Decided 2026-10-11, repo will be public |
| Extra files beyond the brief | `Locales/enUS.lua` (localizable strings), `Core/Slash.lua` (command registry), `tools/setup-test-env.ps1`, `.github/workflows/tests.yml`, `/lp log` command | Needed for the requested localizable table, module subcommands and reproducible tests |
| License | MIT, copyright "snoopjust" (in `LICENSE` and the TOC) | Confirmed 2026-10-11 |
| Shared detection (stage A) | Death/level/instance detection moved from the Ticker into `Core/PlayerEvents` | Ticker and Stats need the same events; modules must not call each other |
| Stats storage (stage A) | Per character inside the account-wide `LooserPimlDB` (`modules.Stats.chars["Name-Realm"]`) | Each client records only its own character; no extra SavedVariables file needed |
| Periods (stage A) | "Tonight" = gaming day starting 06:00 local time; "this week" from Monday 06:00; "all time" = log + rollups | A session past midnight still counts as tonight; same rule on every client |
| Log size (stage A) | Raw log keeps 30 days or 5000 events (whichever first); older events are rolled into daily buckets per type | Small SavedVariables, all-time totals stay exact |
| Counters vs. log (stage A) | Jumps, food/drink, group time are counters in daily buckets, not log entries | Far too frequent for individual entries |
| Played time per level (stage A) | Own session timer per character; a level counts only if we saw it start ("complete"); Speedrunner uses complete levels only | `RequestTimePlayed` prints to chat; partial levels would make the award meaningless |
| Gold sources (stage A) | Hint from what just happened (quest, repair, flight, mail vs. AH sale mail) first, then the open window (+2 s grace), else "other" | `PLAYER_MONEY` has no reason attached |
| Gathering (stage A) | Loot from a GameObject (`GetLootSourceInfo`) counts as gathered; fishing separately | No API says "this was a node"; chests also count (see open questions) |
| Zones discovered (stage A) | First time this character is seen in a zone/subzone since install | The game's exploration state isn't readable per subzone |
| Duels and PvP (stage A) | Only recorded (result, opponent, opponent has LooserPiml); ranked handshake later (stage C) | As specified |
| Sync (stage A) | Only aggregates (never the log), on login/join/change, ≤ 1 per 30 s, BULK priority, replace key so only the newest snapshot waits during a boss; only award-relevant timestamps sent | Keeps traffic to a couple of chunks at most twice a minute |
| Friend (stage A) | Any LooserPiml user seen via HELLO or STATS in a group; cached with class, version, last seen | As specified |
| Awards (stage A) | Highest value wins (lowest for Speedrunner), zero never wins; ties: whoever reached the value first, then name | As specified ("earlier achiever wins") |
| Settings (stage A) | Registry in `Core/Options`; modules keep values in their own SavedVariables; Blizzard panel via proxy settings | Modules stay independent; panel always shows live values |
| Window (stage A) | Generic shell with tab registry; only the Leaderboard tab now; footer version status from friends seen this session (`Version.known`) | Later tabs plug in; the version of offline friends may be outdated anyway |
| Minimap (stage A) | LibDBIcon button + Addon Compartment via `.toc` fields (three intended globals) | As specified; the compartment calls functions by global name |
| `/lp stats` (stage A) | Opens the window; `/lp stats chat` prints the old text ranking | As specified |
| DB schema 2 (stage A) | Banner settings grouped under `Ticker.banner` (hold, size, sound, point); migration moves the v0.1.0 `Ticker.sound` | Old SavedVariables keep working |

## In-game results

First solo session on the Forever beta (2026-10-11):

- Interface **16001** confirmed. Addon loads without Lua errors; `/lp` works.
- Libraries load: CallbackHandler r8, AceComm r14, AceSerializer r5, LibDeflate r3. Encode/compress roundtrip OK (4 chunks).
- `/lp selftest` APIs line: `InChatMessagingLockdown`, `C_InstanceEncounter`, `issecretvalue`, `GetMirrorTimerProgress` and `ADDON_RESTRICTION_STATE_CHANGED` all exist.
- Real own events (solo): death, second death ("Again" variant) and level-up work. Banner and sound work. Not yet tested: drowning, dungeon enter/leave, corpse run, restriction behaviour in real boss fights, anything with a second player.
- **Addon whisper to yourself does not work** (server: "No player named 'X' is currently playing"). The selftest's real-transport step therefore now uses the group channel and is skipped solo (info line, not a failure). Group delivery incl. the server echo is still to be verified with a friend.

## Open questions

1. **Final addon name**: still the working title "LooserPiml".
2. Results of the in-game checks (TESTING.md). In particular whether regular dungeons are "communication-restricted maps" (TODO #7). If they are, every dungeon event is delivered only after leaving. Then we should decide whether that's acceptable.
3. **Chests count as "gathered"** (both are GameObjects). OK, or should chests be told apart (would need a heuristic)?
4. **"Friends online" in the tooltip** counts friends in your group plus friends on your WoW friends list who are online. Friends only known via Battle.net are not counted (would need BNet APIs). Good enough?
5. **06:00 as the start of a gaming day**: fits your evenings, or another hour?
6. **Stats traffic**: while you are active in a group, one stats message (about 2 chunks) at most every 30 s. Fine, or rather every 60 s?

## Next steps

1. **Stage A in-game test** (TESTING.md 2.6, TODO #26–44), then decide whether to tag **v0.2.0** (not tagged yet, waiting for your go).
2. Remaining v0.1.0 checks: sections 2.4/2.5 (drowning, dungeons, restrictions) and section 3 with a friend; WowUp install on a friend's PC (TODO #22).
3. Later stages of the stats/UI work: Profiles tab, Tonight tab with evening recap, PvP tab, ranked duel handshake (stage C). The data for all of them is already being collected.
4. Next modules, all built on Core (Comm handlers, `DB:GetModuleDB`, Roster, TestMode sims, Slash, Options, Window tabs):
   - **Group Inventory**: each client scans its own bags/bank (C_Container) on change, debounced, and sends a compact diff with BULK priority. Watch the addon-message budget; only send on change, never on a timer.
   - **Profession Directory**: each client shares its own professions and known recipes once per session or when they change. "Who can craft X?" lookup. Read-only, no automation of crafting.
   - **Group Bets**: bets on Ticker events ("Max dies before level 20"). Purely social bookkeeping. No gold handling or trade automation; settling is manual between friends. Needs a conflict-free shared state (owner-authoritative per bet).
5. Later: more Ticker events (e.g. first kill of a boss, from the recorded `encounter` events).
