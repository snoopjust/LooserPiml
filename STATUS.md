# Status

_Last updated: 2026-10-19 (stage C1: ranked duels between LooserPiml friends, PvP tab, Duel King; v0.2.0-beta.3 for the duel test with a friend this weekend, before the beta ends on 22 Oct)_

## Done

**Core concept (2026-10-12):** the core unit is the circle of listed LooserPiml friends, not the WoW party/raid. Friends often play separately and only sometimes group up; every feature works between connected friends whether or not anyone is grouped. Grouping is context only (e.g. time grouped with a friend), never a precondition.

- **Core**, reusable by later modules:
  - `Core/Init.lua`: namespace, core-service registry, module registry (enable/disable at runtime, persisted toggle), lifecycle (ADDON_LOADED → PLAYER_LOGIN), `ns.SafeCall` error isolation, `ns.IsSecret`.
  - `Core/Events.lua`: central dispatcher (owners, method or function handlers, internal `LP_*` messages, skips events the client doesn't know), boss-encounter state with a lost-event safety net and test-mode simulation.
  - `Core/DB.lua`: `LooserPimlDB` with `schemaVersion` and ordered migrations, defaults, per-module storage.
  - `Core/Log.lua`: ring buffer, debug output, capture of `ADDON_ACTION_BLOCKED`/`FORBIDDEN`/`LUA_WARNING` and our Lua errors (error-handler hook only in debug/test mode).
  - `Core/Roster.lua`: group members as `Name-Realm`, class colors, connection state (context only), fake friends for test mode.
  - `Core/Friends.lua`: the explicit, mutual LooserPiml friends list, WoW friends list candidates, online state, handshake state, and `Route()`, which decides for every message which connected friends get it (one whisper each).
  - `Core/Comm.lua`: AceComm prefix `LPiml`, AceSerializer + LibDeflate, protocol versioning, one WHISPER per recipient from Friends (never a group channel), drops messages from senders who aren't listed, hold queue during restrictions, retry of refused sends, duplicate filter, test loopback (test messages never go out later), self-test ping.
  - `Core/Version.lua`: HELLO handshake only with listed friends (after login, when they come online, when added; per-friend cooldown), which also proves the friendship is mutual; local warnings for older/newer/incompatible versions.
  - `Core/TestMode.lua`: loopback, fake friends (incl. outdated version), simulation registry, `/lp sim boss`, `/lp selftest` (real transport via a connected friend's echo).
  - `Core/Slash.lua`: `/lp` and `/looserpiml` with a registry for module subcommands.
  - `Core/PlayerEvents.lua` (stage A): detection of the own player's death (incl. drowned), level-up, instance enter/leave, shared by Ticker and Stats via `LP_*` messages.
  - `Core/Util.lua` (stage A): localized GlobalStrings matching, money/duration formatting.
  - `Core/Options.lua` (stage A): settings registry + Blizzard Settings panel, confirmation dialogs.
  - `Core/Window.lua` (stage A): main window shell with tab registry, minimap button (LibDataBroker + LibDBIcon), Addon Compartment entry, footer version status.
  - `Core/FriendsPanel.lua`: the friends list UI (add by name, add from group, add from the WoW friends list, remove), as the Friends tab and as the settings page Options › AddOns › LooserPiml › Friends.
- **Ticker module**: level up, death (+ drowned), dungeon/raid enter/leave. Each client detects only its own events, shows them locally and whispers them to every connected LooserPiml friend, grouped or not. Receivers choose "Ticker messages from friends": banner (default), chat line only, or off. Friends entering/leaving the same instance together get one banner ("Max and Lootius entered The Deadmines."). Center banner (queue, fade, class colors, configurable time/size/position, sound) + local chat line. Held during encounters and shown afterwards ("During the boss: …"). Per-type display filters. Session counters for the banner text; `/lp stats chat` prints the old text ranking.
- **Stats module** (stage A): per-character event log (death, level-up with played time, quests, gold with source, rare loot, instances, boss kills/wipes, crafting/gathering/skill-ups, travel, duels, battlegrounds, honor) plus live counters (jumps, food/drink, chests, group time per friend); rollup into daily buckets (30 days / 5000 events); aggregates per tonight / this week / all time; sharing of aggregates with connected LooserPiml friends, grouped or not (≤ 1 per 30 s, share setting), stats cache per friend with last seen; Leaderboard tab with Hall of Fame (Death King, Fish Food, Gold Hoarder by current gold, Speedrunner) and ranking (deaths, current gold, quests, level-ups).
- **Inventory module** (stage B): own bags (debounced), bank (snapshot while open, with time) and gold; full snapshot after the handshake and deltas (≤ 1 per 30 s) to connected friends; friends' cache for offline display; sharing switches for bags/bank and gold. Friends' inventory tab (gold bar, search, filters, rows with holder chips, last updated). Wishlists: own list (edit), friends' lists (read-only), "wishloot" ticker event.
- **Profiles tab** (stage B): one player in depth from the synced all-time aggregates plus profile extras (professions, favourite zone, evenings played); "—" where there is no data.
- **Tonight tab** (stage B): awards with data, KPI tiles, timeline (Core/Timeline, 7 days); one-time "Last evening" popup.
- **Ranked duels** (stage C1): "ranked?" handshake with a connected friend (panel below the game's duel dialog, Ranked / Just for fun, whispered to the opponent only; LooserPiml never calls a duel action or touches the dialog), own records per opponent and own ranked duels with a shared id, synced with STATS and merged from both sides (disputed duels left out); PvP tab (ladder, head to head matrix Ranked / All duels, battleground placeholder), `duel_ranked` banner / `duel_fun` chat line, Duel King, profile rows, three settings, `/lp sim duel`.
- **Tests**: 255 busted specs, all green, running the real addon + real libraries (incl. LibDBIcon) under Lua 5.1, with several clients talking to each other, grouped and not grouped. The mock delivers whispers only to online players, and every single `SendAddonMessage` call in the suite must be a WHISPER to a listed friend.
- **Tooling**: `tools/fetch-libs.ps1`, `tools/link-addon.ps1` (junction created: `<WoW>\_classic_beta_\Interface\AddOns\LooserPiml` → repo), `tools/setup-test-env.ps1`, `tools/run-tests.ps1`.
- **Distribution**: `.pkgmeta` (libs as git externals, pinned), GitHub Actions `tests.yml` (push/PR) and `release.yml` (tag `v*` → tests → BigWigsMods/packager → GitHub release + `release.json`).
- **Published** (2026-10-11): public repo https://github.com/snoopjust/LooserPiml. Release **v0.1.0** built by CI (tests 78/78 green on Ubuntu, packager job green): `LooserPiml-v0.1.0-forever.zip` with all libraries embedded, `## Version: v0.1.0`, no dev files; `release.json` flavor `forever`, interface 16001. Known cosmetic issue: LibDeflate's docs/examples (~170 KB) are included in the zip.
- **Pre-release v0.2.0-beta.1** (2026-10-12), built by CI from tag `v0.2.0-beta.1` (tests 178/178 green): GitHub release marked **Pre-release** (`prerelease: true`, the packager sets it for tags containing "beta"), asset `LooserPiml-v0.2.0-beta.1-forever.zip` (82 files, all `.toc` entries present incl. LibDataBroker/LibDBIcon, no dev files, `## Version: v0.2.0-beta.1`) and `release.json` (flavor `forever`, interface 16001). `release.json` itself has no pre-release field; WowUp reads GitHub's flag and offers the release only on the Beta channel (checked in WowUp's source; in practice: TESTING.md TODO #54).
- **Docs**: README (friends' install via WowUp + manual), ARCHITECTURE.md (files, load order, end-to-end event diagram, restriction handling), CLAUDE.md (conventions), TESTING.md (solo + two-client checklists, all `TODO(verify in-game)` items), CHANGELOG.

## Safety rules

Every feature is checked against these:

1. Official in-game Lua/XML API only. No external tools, no client modification, no memory reading.
2. Secret/protected values are never circumvented, derived or reconstructed. Every comparison or arithmetic on API data is preceded by `ns.IsSecret`; if secret, the value is dropped and the feature degrades (e.g. no "drowned" variant, unknown class → uncolored name, unknown encounter state → treated as restricted).
3. No visible chat output to anyone. Sync is hidden addon messages via AceComm only. Display is local (own frame, `DEFAULT_CHAT_FRAME:AddMessage`). The test mock errors on any `SendChatMessage`.
4. No automation of game actions.
5. All traffic through ChatThrottleLib. Messages only on real events; HELLO at most once per friend per 10 s; held queue capped (50), retries every 5 s with at most 5 attempts.
6. Plain readable code, free, no ads, no donation requests.
7. Debug/test mode shows blocked/forbidden actions and Lua errors immediately.
8. **Communication only with the explicit, mutual LooserPiml friends list** (added 2026-10-12). Players without LooserPiml, or who aren't on the list, never receive anything from LooserPiml, not even hidden addon messages:
   - Sending: only to listed friends, always as one WHISPER addon message per connected friend (listed + answered the handshake + online on the character friends list or as a connected group member). Never PARTY, RAID or INSTANCE_CHAT (updated 2026-10-12: no special cases for mixed groups), never GUILD, never Battle.net.
   - No discovery broadcasts. The version handshake runs only with listed friends.
   - Receiving: every message from a sender who isn't on the own list is dropped before it is decoded (mutual opt-in, like a friend request).
   - Leaderboard, "friends online" and stats sync include only listed friends who answered the handshake.
   - Test mode and sample friends never send anything to real players.
   - Enforced in code by `Core/Friends.lua` (`Route`) and `Core/Comm.lua`; enforced in tests by a check on every send in every spec.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Repo location | Local working folder chosen by the developer. Repo root = addon folder | As requested |
| Client folder | `<WoW>\_classic_beta_` | Has `WowB.exe`, flavor `wow_classic_beta`; addon guides confirm it is the Forever beta |
| TOC | One `LooserPiml.toc`, `## Interface: 16001` | Warcraft Wiki TOC table lists 16001 for Forever beta; the packager maps `16xxx` → game type `forever` |
| Libraries | Ace3 **Release-r1403** (2026-08-12: AceComm r14, ChatThrottleLib v32), LibDeflate **1.0.2-release**, LibDataBroker **v1.1.4** (GitHub) and LibDBIcon **v12.1.1** (WoWAce SVN), pinned in `.pkgmeta` and `fetch-libs.ps1` | Reproducible builds. LibDBIcon only exists in SVN; the packager installs svn by itself, local dev fetches the two files over HTTPS |
| Prefix / protocol | `LPiml`, protocol 1, envelope `{v,t,s,id,d,late}` | Short, under 16 chars; `s` (random session id) keeps ids unique across /reload |
| Own events | Shown locally right away (own messages are never echoed back) | Works solo and during restrictions; no double banners |
| Restriction handling | Hold if an encounter is active (our ENCOUNTER_START/END tracking or `C_InstanceEncounter.IsEncounterInProgress`) or `C_ChatInfo.InChatMessagingLockdown()`. Also hold and retry when AceComm reports `didSend == false`. Flush on `LP_ENCOUNTER_END`, `ADDON_RESTRICTION_STATE_CHANGED` (Inactive), `PLAYER_ENTERING_WORLD`, and a 5 s retry ticker | Covers the documented APIs plus the actual result codes, without relying on one signal |
| "Late" marker | Messages held for an encounter carry `late = "encounter"`, so receivers show "During the boss: …". Other lockdowns carry `"lockdown"` and show "Earlier: …" | Receivers otherwise can't tell old news from new |
| Banners during encounters | Held (own too), max 5 shown afterwards + "… and N more", with a 2 s watcher in case no end event arrives | Don't distract mid-fight |
| Core unit (2026-10-12) | The circle of listed LooserPiml friends, not the WoW group. Every feature works between connected friends whether or not anyone is grouped; grouping is context only | Decided: friends often play separately (2 of 5 online) and only sometimes group up |
| Transport (2026-10-12) | Always one WHISPER addon message per connected friend; PARTY/RAID/INSTANCE_CHAT are never used, not even when the whole group is friends | Decided: keeps the friends-only rule simple, no special cases for mixed groups. Cost: one copy per friend (five friends online = five whispers), throttled by ChatThrottleLib |
| Test mode | Not saved (off after /reload). Sims only in test mode. Test events never touch all-time stats | Avoid "why does nothing reach my friend" and fake stats |
| Dev builds | `@project-version@` → "dev", never compared, except in test mode, where dev = 1.0.0 so the warnings can be tried solo | Dev checkout playing with friends must not spam warnings |
| Icons | Raid target textures instead of emoji | WoW fonts have no emoji glyphs |
| Drowning | Drowned if the BREATH timer was draining and ≤ 1000 ms were left at death, or it stopped ≤ 1.5 s before death with ≤ 1000 ms left. Uses `GetMirrorTimerProgress` when > 0, else the START payload | No combat log needed (CLEU is unavailable in Midnight/Forever) |
| Corpse runs | No "left" while dead/ghost; re-entering the same instance within 10 min is quiet | Avoids enter/leave spam on wipes |
| Raids | Count as instances for enter/leave (confirmed 2026-10-11) | Wanted by the friends; same code path as dungeons |
| Language | English only for now; strings stay in `Locales/enUS.lua` so a translation can be added later | Decided 2026-10-11 |
| Git identity / privacy | Commits use the GitHub noreply address (`git config --local user.email`); history rewritten before the first push so no commit contains the private email or machine-specific paths (drive letters, usernames) | Decided 2026-10-11, repo will be public |
| Extra files beyond the brief | `Locales/enUS.lua` (localizable strings), `Core/Slash.lua` (command registry), `tools/setup-test-env.ps1`, `.github/workflows/tests.yml`, `/lp log` command | Needed for the requested localizable table, module subcommands and reproducible tests |
| License | MIT, copyright "snoopjust" (in `LICENSE` and the TOC) | Confirmed 2026-10-11 |
| Shared detection (stage A) | Death/level/instance detection moved from the Ticker into `Core/PlayerEvents` | Ticker and Stats need the same events; modules must not call each other |
| Stats storage (stage A) | Per character inside the account-wide `LooserPimlDB` (`modules.Stats.chars["Name-Realm"]`) | Each client records only its own character; no extra SavedVariables file needed |
| Periods (stage A) | "Tonight" = gaming day starting 06:00 local time; "this week" from Monday 06:00; "all time" = log + rollups | A session past midnight still counts as tonight; same rule on every client. 06:00 confirmed 2026-10-12 |
| Log size (stage A) | Raw log keeps 30 days or 5000 events (whichever first); older events are rolled into daily buckets per type | Small SavedVariables, all-time totals stay exact |
| Counters vs. log (stage A) | Jumps, food/drink, group time are counters in daily buckets, not log entries | Far too frequent for individual entries |
| Played time per level (stage A) | Own session timer per character; a level counts only if we saw it start ("complete"); Speedrunner uses complete levels only | `RequestTimePlayed` prints to chat; partial levels would make the award meaningless |
| Inventory (2026-10-14) | Own character only, never equipped items. Bags: backpack, bags 1-4, reagent bag, rescanned 2 s after the last `BAG_UPDATE_DELAYED`. Bank: `Characterbanktab` + `CharacterBankTab_1-9`, read only while open (snapshot + time). Account bank tabs left out (they belong to the account) | As specified; Forever's `Enum.BagIndex` checked in Blizzard's Forever UI code (TODO #55 in practice) |
| Inventory sync (2026-10-14) | INV full after a handshake / on INVREQ / after a sharing switch; INV delta with absolute counts, ≤ 1 per 30 s, BULK; session id + sequence number, a delta that doesn't fit triggers one INVREQ per minute | Small traffic, self-healing after a missed message. A full snapshot of 300 items ≈ 0.9 KB (4 chunks) |
| Sharing switches (2026-10-14) | "Share my bags and bank" and "Share my gold" in the Inventory section, stored in `LooserPimlDB.share` (Stats needs gold too). Off: nothing of that kind is sent and friends drop their cache (new full snapshot without it) | As specified; modules don't call each other, so the switch lives in core storage |
| Wishlists (2026-10-14) | Own list only (max 30, item + quantity, typed name / ID / shift-click), WISH = the whole list, stored under the sender only. "N among friends" counts everyone except the owner (for my own wish: everyone incl. me). Wishlist loot → `LP_WISHLIST_LOOT` → Ticker "wishloot" (sender includes item name, quality, owner, still needed) | As specified; no way to edit a friend's list by design |
| Timeline (2026-10-14) | Core service, fed by the Ticker with own and friends' events (text + icon), 7 days / 1000 entries | Needed by Tonight and wishlists; modules don't call each other |
| Profiles (2026-10-14) | New counters `playedSeconds` (our session timer) and `firstDeaths` (first death of an instance visit among me and my friends); STATS extras `prof`, `fav` (zone most frequent in the own log), `eve` (days with activity). Played and grouped time are counted quietly (no message per minute) | Compact and backwards compatible; older clients ignore unknown fields, the profile shows "—" |
| Tonight / recap (2026-10-14) | KPIs summed over me + friends' "tonight"; session = since login, at the earliest 06:00; recap popup once per evening for the last active day before today (setting "Show evening recap") | As specified |
| Gold Hoarder / Gold (2026-10-14) | Award and ranking use the gold on hand right now (a snapshot sent with STATS as `gold`), not gold looted; the period selector doesn't apply to it (note "right now"). Setting "Share my gold" (default on): without it, no `gold` is sent and that friend (or you, on your own screen) is left out of both. Gold by source is still recorded | Decided by the user. A message without `gold` clears the cached value, so turning it off takes effect with the next stats message |
| Gold sources (stage A) | Hint from what just happened (quest, repair, flight, mail vs. AH sale mail) first, then the open window (+2 s grace), else "other" | `PLAYER_MONEY` has no reason attached |
| Gathering (2026-10-12) | "Gathered" = profession gathering only: a loot window right after a Herb Gathering / Mining / Skinning cast (matched by localized spell name, all ranks), or fishing (`IsFishingLoot`) | Decided: chests don't count as gathered. No API says "this was a node", the cast before the loot window does |
| Chests (2026-10-12) | Loot from any other GameObject with at least one non-quest item counts as `chestsOpened` (a counter, not shown in the UI yet). Nothing is counted if the cast before the loot window was secret | Decided: separate counter. Quest objects on the ground are GameObjects too; only-quest-item loot is skipped |
| Zones discovered (stage A) | First time this character is seen in a zone/subzone since install | The game's exploration state isn't readable per subzone |
| Duels and PvP (stage A) | Only recorded (result, opponent, opponent has LooserPiml); ranked handshake later (stage C) | As specified |
| Ranked handshake (2026-10-19) | Panel only for a duel with a *connected* friend. Challenged side: `DUEL_REQUESTED` → new duel id → DUEL `ask` to the challenger. Challenger side: `StartDuel` post-hook opens the panel early; the friend's `ask` opens it too if the hook missed it (the reliable signal; TODO #64). Picks, `start` (AcceptDuel post-hook) and `close` (CancelDuel post-hook) go to the opponent only (`to`). Ranked = both picked Ranked before the result line | The API has no outgoing-request event; the friend's own DUEL_REQUESTED, relayed as a whisper, is the dependable signal. No protected or game action is needed anywhere |
| Panel timing (2026-10-19) | The panel closes 3 s after the accept (the countdown, no start event exists; TODO #66) or at once on decline/withdraw/`DUEL_FINISHED` before the start. The choice stays valid until the result, or 5 s after `DUEL_FINISHED` without a result line | "Panel closes when the duel starts": closing on the accept itself would cut off the challenged player, who often clicks Accept first |
| Who announces (2026-10-19) | Only the winner's client sends the `duel_ranked` / `duel_fun` TICK; the loser gets it like any friend's event | One banner per duel for everyone. Cost: a friend who is listed only by the loser sees no banner (the ladder still shows the duel once both STATS arrive) |
| Ladder merge (2026-10-19) | Each client sends only its own ranked duels (`{ id, t, opponent, won }`, newest 60) and per-opponent record, only against listed friends. A duel counts once both sides' records name each other and exactly one says won; both say won/lost → disputed (left out); one side only → left out until the other side agrees. The ladder and matrix only pair participants on this screen | As specified ("each client records only its own result; the ladder merges both sides"). Requiring both sides also covers a duel one side didn't count as ranked (a pick that arrived too late). The 60-duel window per player is enough for a small circle; older duels drop off the ladder (~1.1 KB / 5 chunks per STATS with 60 duels) |
| Duel King (2026-10-19) | Confirmed ranked wins in the selected period (`Ladder.Annotate`), not the claimed `rankedWon` counter; ties: whoever reached it first | Consistent with the ladder: disputed duels never crown anyone. The profile's "Ranked duels won / lost" uses the own aggregate (what that player recorded) |
| Duel streak (2026-10-19) | Stored per opponent (ranked, signed: +3 = W3); the ladder's streak is computed from confirmed duels over all opponents | The per-opponent streak is what the spec asked to store; the ladder needs the overall one |
| Fun duels (2026-10-19) | `duel_fun` is a chat line only, never a banner, receiver setting "Fun duel results" (default off). Duels with strangers send nothing | As specified |
| No migration (2026-10-19) | `char.duelRecord`, `char.rankedDuels`, `Stats.askRanked`, `Ticker.show.duelRanked/duelFun` are new optional keys filled by defaults or on first use; `SCHEMA_VERSION` stays 3 | Nothing existing moves or changes meaning, like the stage-B additions |
| Sync | Only aggregates (never the log), to confirmed friends online (scope "friends"): when a friend's handshake arrives and after changes, ≤ 1 per 30 s, BULK priority, replace key so only the newest snapshot waits during a boss; only award-relevant timestamps sent | 30 s confirmed 2026-10-12. Keeps traffic to a couple of chunks at most twice a minute |
| Friend (2026-10-12) | Only players on the explicit LooserPiml friends list, added by name or from the group. Stored in `LooserPimlDB.friends` with added, last handshake, last seen, class, version. Max 40 | Decided: rule 8. Replaces the stage-A "anyone seen in a group" |
| Mutual / handshake (2026-10-12) | A listed friend who answers our HELLO (or greets us) has listed us too: their client drops our messages otherwise and never answers. "Confirmed" lasts for the session and is forgotten when the friend goes offline; the next contact needs a fresh handshake | The only way to learn "mutual" without asking anyone who isn't listed |
| Scopes (2026-10-12) | HELLO: listed friends online ("handshake"). Everything else (TICK, STATS, self-test): connected friends ("friends"). A one-sided friend gets only HELLOs | Decided: ticker events go to all connected friends, grouped or not |
| Ticker display (2026-10-12) | "Ticker messages from friends": Banner (default) / Chat line only / Off, on top of the per-type toggles; own events keep "Also show my own events". Friends' events are counted for the stats either way. Enter/leave of the same instance within 2 s are combined into one banner with all names | Decided. With friends playing everywhere, banners for everyone can be too much for some |
| Online (2026-10-12) | Online on the character friends list (`C_FriendList`), or a connected group member (`UnitIsConnected`). No Battle.net. Exception: a handshake reply may go to a friend who wrote to us within 30 s | Whispering someone offline makes the server print "No player named ..."; friends should be WoW friends too, the UI says so |
| Routing time (2026-10-12) | Recipients are decided when a message really goes out, not when it is queued | A message held during a boss respects a friend removed or a stranger who joined meanwhile |
| Test mode messages (2026-10-12) | Messages created in test mode are dropped if test mode is off by the time they would be flushed; the self-test's real transport is skipped in test mode; fake friends can't be added to the friends list | Rule 8: test mode never reaches real players |
| Self-test (2026-10-12) | The real-transport step whispers a multi-chunk payload to one connected friend; their client whispers it back (at most once per 10 s per friend) | No group channel any more, and whispers to yourself are rejected by the server |
| Friends UI (2026-10-12) | Friends tab in the main window and the settings page Options › AddOns › LooserPiml › Friends (a canvas page, linked from a "LooserPiml friends" section on the main page). Add by name, from the group, or from the WoW friends list (online first), with a hint to be WoW friends too. A one-time chat hint after login while the list is empty. `/lp friends` for power users | A list with a remove button per row needs its own frame; the Blizzard vertical layout can't change rows at runtime |
| Wording (2026-10-12) | "Friends", never "group": window "LooserPiml · Friends", "Share my stats with my LooserPiml friends", "fake friends" in test mode, later "Friends' inventory" | Decided with the core-unit change |
| DB schema 3 (2026-10-12) | New top-level `friends`; the stage-A stats cache (`Stats.friends`, filled from anyone in the group) is dropped, received stats now live in `Stats.friendStats` | Nobody opted in to that data. The friends list starts empty on purpose |
| Awards (stage A) | Highest value wins (lowest for Speedrunner), zero never wins; ties: whoever reached the value first, then name | As specified ("earlier achiever wins") |
| Settings (stage A) | Registry in `Core/Options`; modules keep values in their own SavedVariables; Blizzard panel via proxy settings | Modules stay independent; panel always shows live values |
| Window (stage A) | Generic shell with tab registry; tabs Leaderboard and Friends; footer version status from friends heard from this session (`Version.known`) | Later tabs plug in; the version of offline friends may be outdated anyway |
| Minimap (stage A) | LibDBIcon button + Addon Compartment via `.toc` fields (three intended globals) | As specified; the compartment calls functions by global name |
| `/lp stats` (stage A) | Opens the window; `/lp stats chat` prints the old text ranking | As specified |
| DB schema 2 (stage A) | Banner settings grouped under `Ticker.banner` (hold, size, sound, point); migration moves the v0.1.0 `Ticker.sound` | Old SavedVariables keep working |

## In-game results

First solo session on the Forever beta (2026-10-11):

- Interface **16001** confirmed. Addon loads without Lua errors; `/lp` works.
- Libraries load: CallbackHandler r8, AceComm r14, AceSerializer r5, LibDeflate r3. Encode/compress roundtrip OK (4 chunks).
- `/lp selftest` APIs line: `InChatMessagingLockdown`, `C_InstanceEncounter`, `issecretvalue`, `GetMirrorTimerProgress` and `ADDON_RESTRICTION_STATE_CHANGED` all exist.
- Real own events (solo): death, second death ("Again" variant) and level-up work. Banner and sound work. Not yet tested: drowning, dungeon enter/leave, corpse run, restriction behaviour in real boss fights, anything with a second player.
- **Addon whisper to yourself does not work** (server: "No player named 'X' is currently playing"). The selftest's real-transport step therefore pings a connected friend, whose client echoes it (since 2026-10-12; solo it is an info line, not a failure). Whisper delivery between friends is still to be verified with a friend.

## Open questions

1. **Final addon name**: still the working title "LooserPiml".
2. Results of the in-game checks (TESTING.md). In particular whether regular dungeons are "communication-restricted maps" (TODO #7). If they are, every dungeon event is delivered only after leaving. Then we should decide whether that's acceptable.
3. **Account bank**: the account-wide bank tabs are not shared (they belong to the whole account, not to the character). Include them?
4. **"First to die in a dungeon"** compares the zone of friends' deaths with the instance name (TODO #60). If Forever reports a different zone inside instances, it would count too often.
5. **Ranked duels, in-game unknowns** (TODO #63–68): whether the `StartDuel` post-hook sees the unit menu and `/duel`, the order of `DUEL_FINISHED` and the result line, the countdown length. All have fallbacks (the friend's ask, a 5 s grace, closing on the accept + 3 s).

Resolved 2026-10-12: chests are a separate counter (not gathered); communication only with the explicit, mutual friends list (no Battle.net); "tonight" starts at 06:00; stats at most every 30 s; the circle of friends is the core unit, ticker events reach all connected friends (whisper-only transport).

## Next steps

1. **Two-player test with v0.2.0-beta.3** this weekend, before the Forever beta ends on 22 Oct (pre-release; TESTING.md section 3 incl. the new duel block 3.5, plus 2.6–2.9 and TODO #26–69), then decide whether to tag **v0.2.0**. Every friend has to add the others to their WoW friends list and their LooserPiml friends list first.
2. Remaining v0.1.0 checks: sections 2.4/2.5 (drowning, dungeons, restrictions) and section 3 with a friend; WowUp install on a friend's PC (TODO #22).
3. Stage C next: battleground stats in the PvP tab (placeholder is there; the data is already collected).
4. Next modules, all built on Core (Comm handlers, `DB:GetModuleDB`, Roster, TestMode sims, Slash, Options, Window tabs):
   - **Profession Directory**: each client shares its own professions and known recipes once per session or when they change. "Who can craft X?" lookup. Read-only, no automation of crafting.
   - **Friends' bets**: bets on Ticker events ("Max dies before level 20"). Purely social bookkeeping. No gold handling or trade automation; settling is manual between friends. Needs a conflict-free shared state (owner-authoritative per bet).
5. Later: more Ticker events (e.g. first kill of a boss, from the recorded `encounter` events).
