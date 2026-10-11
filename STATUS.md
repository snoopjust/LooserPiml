# Status

_Last updated: 2026-10-11 (initial scaffold, Core + Ticker MVP)_

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
- **Ticker module**: level up, death (+ drowned), dungeon/raid enter/leave. Each client detects only its own events, shows them locally and broadcasts them. Center banner (queue, fade, class colors) + local chat line. Held during encounters and shown afterwards ("During the boss: …"). Stats per player (session + all-time), `/lp stats` with Death King.
- **Tests**: 78 busted specs, all green, running the real addon + real libraries under Lua 5.1, including two clients talking to each other.
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
| Libraries | Ace3 **Release-r1403** (2026-08-12: AceComm r14, ChatThrottleLib v32) and LibDeflate **1.0.2-release**, from GitHub, pinned in `.pkgmeta` and `fetch-libs.ps1` | Reproducible builds; git externals need no SVN in CI |
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

## Next steps

1. Run TESTING.md sections 2 and 3, and fill in the TODO table (paste the `/lp selftest` APIs line here).
2. Install v0.1.0 via WowUp ("Install from URL" → https://github.com/snoopjust/LooserPiml) on a friend's PC to confirm WowUp picks the `forever` flavor (TESTING.md TODO #22).
3. Next modules, all built on Core (Comm handlers, `DB:GetModuleDB`, Roster, TestMode sims, Slash):
   - **Group Inventory**: each client scans its own bags/bank (C_Container) on change, debounced, and sends a compact diff with BULK priority. Watch the addon-message budget; only send on change, never on a timer.
   - **Profession Directory**: each client shares its own professions and known recipes once per session or when they change. "Who can craft X?" lookup. Read-only, no automation of crafting.
   - **Group Bets**: bets on Ticker events ("Max dies before level 20"). Purely social bookkeeping. No gold handling or trade automation; settling is manual between friends. Needs a conflict-free shared state (owner-authoritative per bet).
4. Later: optional settings UI (out of scope for now), more Ticker events (e.g. first kill of a boss, which needs `ENCOUNTER_END` success).
