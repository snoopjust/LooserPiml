# Testing LooserPiml

There are three levels:

1. **Offline** (busted). Runs on every change and in CI.
2. **In-game solo** with one account: test mode, simulations and `/lp selftest`.
3. **Two clients**: a 15-minute session with one friend.

Anything that can't be verified offline is marked `TODO(verify in-game)` in
the code. All of these are collected at the end of this file. Tick them off
(or note what happened) as you test.

---

## 1. Offline (busted)

```bash
powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1
```

Setup is in the [README](README.md#tests). `spec/support/wow_mock.lua` mocks
the WoW API. `spec/support/helpers.lua` loads every file in `.toc` order,
**real libraries included**, into one isolated environment per simulated
client. Several clients can share a mock network, so messages really go
through AceComm, ChatThrottleLib, chunking and decoding.

The mock enforces the safety rules. Calling `SendChatMessage` raises an
error. Addon messages must be 255 bytes or less and contain no NUL. Every
test fails if a Lua error reached any client's error handler. A hygiene test
fails if the addon leaks globals.

Covered:

| Area | Spec |
|---|---|
| Loading in .toc order, lifecycle, module enable/disable, DB migrations, event isolation, blocked-action logging, slash commands, self-test (incl. timeout and lockdown), secret values from Roster/encounter APIs | `core_spec.lua` |
| Serialize/compress roundtrip (all byte values), multi-chunk transport between two clients, RAID/solo channel choice, echo/duplicate/protocol filtering, hold queue + flush around encounters and lockdown, retry of refused sends, give-up, stale drop, queue cap, test-mode loopback | `comm_spec.lua` |
| Version parse/compare, login handshake, outdated/newer warnings (once), HELLO reply rules, coalescing, protocol mismatch, dev builds, fake group versions | `version_spec.lua` |
| Stats counting, test events excluded from all-time, ranking, Death King report, persistence across reload | `stats_spec.lua` |
| Death/level-up/enter/leave detection, duplicate deaths, drowning (incl. event order, secret values), corpse runs, receiving + sanitizing, encounter hold + "During the boss", `/lp sim` → loopback → receive → stats → display, two-client end-to-end, banner sound | `ticker_spec.lua` |
| Localized format strings → patterns (positional args, secret text), money/duration formatting | `util_spec.lua` |
| Gaming day/week periods (06:00 boundary), aggregation per event type, merge, rollup + cap without changing totals, aggregation per period, sanitizing received aggregates | `stats_model_spec.lua` |
| Recording per event type with mocked events: death, level-up (played time), quests, instances, boss kills/wipes, money sources (merchant, repair, loot grace, mail, AH mail, flight, quest), travel, jumps, food/drink, group time, rare loot, crafting, gathering, skill-ups, duels, battlegrounds, honor; collect off; compaction; simulated events never recorded | `stats_collect_spec.lua` |
| Sync: exchange on login/changes, ≤ 1 broadcast per 30 s, share off = nothing sent, staleness of tonight/week, cache survives reload (offline friends), hostile payloads, boss-fight queue with newest snapshot only, message size, sample friends | `stats_sync_spec.lua` |
| Awards incl. ties and empty data, ranking rows and bar fractions, formatting, ranking with real synced data | `leaderboard_spec.lua` |
| Option defaults, v0.1.0 → v0.2.0 migration, ticker filters, own events, boss recap, banner time/size/move/reset, Blizzard panel build with live proxy values, reset confirmation, testing buttons | `options_spec.lua` |
| Window open/ESC/toggle/position, leaderboard contents and selectors, minimap button clicks, tooltip lines, minimap hide/show, Addon Compartment callbacks, footer version status | `window_spec.lua` |

---

## 2. In-game solo (one account)

Dev setup: run `tools\fetch-libs.ps1` once. The junction from
`tools\link-addon.ps1` already points the Forever beta client at the repo.

### 2.1 Load + basics

- [ ] `/dump select(4, GetBuildInfo())` prints **16001**. If not, update `## Interface:` in `LooserPiml.toc`.
- [ ] The character select AddOns list shows LooserPiml as enabled, not "out of date".
- [ ] No Lua error on login. Tip: `/console scriptErrors 1`, or use BugSack.
- [ ] `/lp` prints the help.
- [ ] `/lp debug on`, then `/reload`. Debug mode is still on, so SavedVariables persist.

### 2.2 Self-test (real transport)

- [ ] `/lp selftest`. Expected:
  - `[OK] Libraries: CallbackHandler-1.0 r.., AceComm-3.0 r14, AceSerializer-3.0 r.., LibDeflate r..`
  - `[OK] Serialize + compress roundtrip (... bytes on the wire, N chunks)` with N ≥ 3
  - `[OK] Loopback dispatch`
  - `[INFO] Client APIs: ...`. **Copy this line into STATUS.md.** It answers several TODOs below.
  - Solo: `[INFO] Real transport: not tested, you are not in a group`. That's expected: the Forever server rejects whispers to yourself ("No player named X is currently playing"), so there is no solo transport test.
  - In a group: `[OK] Real transport: echo received after X s, payload intact`. This sends a multi-chunk message on the group channel and checks that the server echoes it back.
- [ ] If the echo times out in a group, note the exact message; check section 3 as well.

### 2.3 Test mode + simulations

- [ ] `/lp test on`. The message lists Max, Lena, Jo and Kim. About 1 s later: "Kim runs an older LooserPiml (...)" and "Jo has a newer LooserPiml (...)".
- [ ] `/lp version` lists the fake members with their versions.
- [ ] `/lp sim death Max`. A banner shows a skull icon, "[test]" and **Max** in warrior brown. A chat line starting with `[LP]` appears too.
- [ ] Run `/lp sim death Max` 2 more times. The text switches to the "Again" variants with the count.
- [ ] `/lp sim drown Lena`, `/lp sim levelup Jo`, `/lp sim enter Kim`, `/lp sim leave`, `/lp sim death`. All show, queued one after another, fading.
- [ ] `/lp sim boss`. Nothing shows for about 10 s, then "During the boss: ... Max died." and your own death appear.
- [ ] `/lp stats`. Death King: Max. Test events count for this session only; all-time stays empty.
- [ ] `/lp test off`, then `/lp sim death Max` refuses: "only run in test mode".
- [ ] Icons render (raid target skull/star/...) and the banner font is readable.

### 2.4 Real own events (solo)

- [ ] Die (e.g. fall damage). You see "Me died." once, not twice.
- [ ] Release, run back, resurrect, die again. You get an "Again" variant.
- [ ] **Drowning**: swim down and wait until the breath bar is empty and you die. You should get the "drowned" variant. With `/lp debug on`, watch the order of events.
- [ ] Enter a dungeon: "entered <name>". Leave alive: "left <name>". Die inside, release, run back in: no enter/leave spam.
- [ ] Level up: "reached level N!" with the correct N.

### 2.5 Restrictions, solo

The game has test switches that force its addon restrictions. They're not
saved, so a restart clears them. TODO(verify in-game): do they exist on Forever?

- [ ] `/lp debug on`, then `/console addonChatRestrictionsForced 1`.
- [ ] In a group with anyone (or just watch the debug log): trigger a death. The debug log says "Holding TICK message (lockdown)".
- [ ] `/console addonChatRestrictionsForced 0`. Within a few seconds: "Flushed 1 held message(s)".
- [ ] Same with `addonEncounterRestrictionsForced 1`. Banners are held until it's switched off, then shown within about 2 s (Display re-checks every 2 s, so a missing end event is fine). Note whether `C_InstanceEncounter.IsEncounterInProgress()` reports true while it's forced.
- [ ] No `[Blocked action]` / `[Forbidden action]` line for LooserPiml at any time. If one shows up: **stop and report** (copy `/lp log`).

### 2.6 Stage A (v0.2.0): window, minimap, settings, stats

**Window and minimap**
- [ ] The minimap button (skull) appears. Left-click opens/closes the window, right-click opens the settings, drag moves it around the minimap; the position is kept after `/reload`.
- [ ] The Addon Compartment (addon list button on the minimap) lists LooserPiml once, with icon; left/right click and tooltip work. No duplicate entry.
- [ ] Tooltip: "LooserPiml", click hints, friends online with LooserPiml, deaths tonight, Death King.
- [ ] Window: title "LooserPiml · Group stats", close button, ESC closes it, it can be dragged and stays where it was after `/reload`. Colors look like the mockup (dark brown, bronze borders, gold headings), text is readable.
- [ ] `/lp test on`, then Settings › Testing › "Fill with sample friends": the leaderboard shows four sample friends; period buttons (Tonight / This week / All time) and metric buttons (Deaths / Gold looted / Quests / Level-ups) switch the content; bars look right; names are class-colored.
- [ ] Solo without test mode: the cards say "No one yet" (or show you), with the hint to group up.

**Settings (Esc › Options › AddOns › LooserPiml)**
- [ ] The category exists with the sections Ticker messages, Banner, Stats, Minimap, Testing.
- [ ] Each Ticker checkbox hides its message type (try with `/lp sim ...` in test mode); "Also show my own events" off hides only your own.
- [ ] Banner: display time and size sliders change the next banner; "Unlock / lock" shows a sample banner you can drag, locking makes it click-through again; "Reset banner position" puts it back. Position is kept after `/reload`.
- [ ] Stats: "Reset my stats" asks for confirmation first; "No" keeps everything.
- [ ] Minimap: unticking hides the button, ticking shows it again.
- [ ] Testing buttons work (simulate death / level up / boss fight, sample friends, self-test, debug log).

**Stats collection** (with `/lp debug on`: each recorded event logs "Stats: <type> recorded"; check with `/lp log 30`)
- [ ] Death, level-up (`played` close to `/played` for that level), quest turn-in (with XP and money).
- [ ] Gold: loot coins from a mob (`loot`), sell and buy at a vendor (`vendor_sell` / `vendor_buy`), "Repair all" (`repair`), take gold from a normal mail (`mail`) and from an auction house sale (`ah_mail`), pay a trainer (`trainer`), take a flight (`flight`).
- [ ] Loot a blue/purple item: `loot_rare` with the right quality. Grey/white/green items are not recorded.
- [ ] Craft something (`profession` crafted), gather a herb/ore node (`gathered`), fish (`gathered`, source fishing), get a skill-up (`skillup`; for a profession `profession = true`, for weapon/defense skills `false`).
- [ ] New subzone, flight path, hearthstone are recorded; jumping counts only real jumps (not swimming up or pressing in mid-air); eating and drinking are counted.
- [ ] Duel a friend: win, lose and flee once each; only your own duels are recorded, with the opponent's name.
- [ ] Battleground: joined, finished (won/lost, your killing blows etc.), and leaving early counts as deserted. Honor snapshot after honor changes.
- [ ] No `[Blocked action]` / `[Forbidden action]` line for LooserPiml during any of this, especially while jumping (post-hook on a protected function).

**Sync** (with a friend, see section 3)
- [ ] After grouping, the friend appears on your leaderboard within about 10 s; changes arrive within about 30 s.
- [ ] After the friend logs out and you `/reload`, they are still listed, marked offline.
- [ ] Settings › Stats › "Share my stats" off on one side: the other side stops receiving updates.

---

## 3. Two clients (15 minutes with one friend)

Both: same LooserPiml version (from WowUp or the zip), `/lp debug on`.

1. **Handshake (2 min)**
   - [ ] Invite the friend. Within ~5–10 s `/lp version` on both sides shows the other's version, not "no reply".
   - [ ] One of you on an older release (or a dev build vs. a release): only the newer side sees "runs an older LooserPiml", the older side sees "has a newer LooserPiml". Each warning appears once.
2. **Broadcast (5 min)**
   - [ ] Friend dies. You see the banner with their class color, plus the chat line. They see it once, not twice.
   - [ ] Friend levels up (or use a fresh low-level char). You see "reached level N".
   - [ ] Friend enters/leaves a dungeon while you're outside. You see it.
   - [ ] `/lp stats chat` on your side counts the friend's deaths (session + all-time); the leaderboard window (`/lp stats` or the minimap button) shows them too.
3. **Encounter queue (5 min)**: 5-man dungeon, first boss
   - [ ] During the boss one of you dies. Nobody gets a banner during the fight.
   - [ ] After the boss (kill or wipe) both see "During the boss: X died." within a few seconds.
   - [ ] Debug log on the dying player's side: "Holding TICK message (encounter)", later "Flushed".
   - [ ] Note: does `C_ChatInfo.InChatMessagingLockdown()` return true during the boss? `/dump C_ChatInfo.InChatMessagingLockdown()` (macro it before the pull). And outside bosses but inside the dungeon?
4. **Outdated version warning (2 min)**
   - [ ] If you have no older release handy: one side runs the dev junction (`dev`). No warnings should appear because dev builds are never compared. That's correct.
5. **Afterwards**
   - [ ] `/lp log 50` on both sides. Look for `[warn]`, `[error]`, `blocked`, `forbidden`.
   - [ ] Write the results into STATUS.md.

---

## TODO(verify in-game): open items

| # | What | How to check | Result |
|---|---|---|---|
| 1 | Interface number is 16001 and stays that at launch (Nov 4, 2026) | `/dump select(4, GetBuildInfo())` | **16001 confirmed on the beta (2026-10-11)**. Launch value still open |
| 2 | Client folder name `_classic_beta_` (beta). Launch name? | Look in the WoW folder after launch | |
| 3 | LibStub, CallbackHandler, AceComm r14 + ChatThrottleLib v32, AceSerializer, LibDeflate load on Forever | `/lp selftest` step 1, no Lua errors | **OK (2026-10-11)**: CallbackHandler r8, AceComm r14, AceSerializer r5, LibDeflate r3 loaded, roundtrip OK |
| 4 | Addon whisper to yourself (incl. multi-chunk) is delivered | `/lp selftest` | **No (2026-10-11)**: server answers "No player named 'X' is currently playing" per chunk. Selftest now uses the group channel instead (see #5) |
| 5 | PARTY/RAID addon messages arrive between friends | Section 3.1/3.2 | |
| 6 | During boss encounters: `InChatMessagingLockdown()` is true and/or sends return `AddOnMessageLockdown` (11); messages sent then are dropped, not delayed by the server | Section 3.3, debug log ("refused by the client") | |
| 7 | Are regular dungeons (outside encounters) a "communication-restricted map"? If yes, all dungeon messages are delayed until you leave | `/dump C_ChatInfo.InChatMessagingLockdown()` inside a dungeon | |
| 8 | `ADDON_RESTRICTION_STATE_CHANGED` exists on Forever and fires Inactive (0) when restrictions end | `/lp selftest` APIs line (`RestrictionEvent=`), debug log | Event exists (2026-10-11). Firing on lift: still open |
| 9 | `ENCOUNTER_START`/`ENCOUNTER_END` fire for 5-man bosses on Forever; `C_InstanceEncounter.IsEncounterInProgress` exists | Section 3.3, selftest APIs line | API exists (2026-10-11). Events in a real boss: still open |
| 10 | `CHAT_MSG_ADDON` payloads are never secret, even while locked down. AceComm doesn't check, so this would show as AceComm Lua errors during bosses | BugSack during section 3.3 | |
| 11 | `PLAYER_DEAD` fires once per death; not on login as a ghost | Section 2.4 | **OK (2026-10-11)**: one message per death, "Again" variant on the second death |
| 12 | Drowning: `MIRROR_TIMER_START` BREATH payload (value in ms, scale -1) is not secret; order of `MIRROR_TIMER_STOP` vs `PLAYER_DEAD`; `GetMirrorTimerProgress("BREATH")` at empty breath | Section 2.4 with debug on | |
| 13 | `PLAYER_LEVEL_UP` level argument is a plain number | Section 2.4 | **OK (2026-10-11)**: level-up banner with the correct level |
| 14 | `GetInstanceInfo()` instanceType `party`/`raid` and a stable instanceID on Forever | Section 2.4 | |
| 15 | `UnitName`/`UnitClass` of group members are not secret out of combat (class colors work) | Section 3.2 | |
| 16 | Raid target icon textures and `GameFontNormalHuge` exist and look fine | Section 2.3 | **OK (2026-10-11)**: icon and banner render |
| 17 | SavedVariables persist (an early beta build had a restore bug) | Section 2.1 | |
| 18 | `INSTANCE_CHAT` in dungeon-finder groups (if Forever has one) | Queue together via finder, check 3.2 | |
| 19 | `ADDON_ACTION_BLOCKED`/`FORBIDDEN` payload (addon name first) and `LUA_WARNING` exist | Only if something gets blocked; debug log | |
| 20 | `addonChatRestrictionsForced` / `addonEncounterRestrictionsForced` CVars exist on Forever | Section 2.5 | |
| 21 | Packager action builds the zip with libs, `release.json` flavor `forever` | First tag push: check the release assets | |
| 22 | WowUp (≥ 2.24.0 beta) detects the Forever client and installs from the GitHub URL | Friend installs via section "For friends" in README | |
| 23 | A plain `LooserPiml.toc` (no `_Forever`/`_Camelot` suffix) loads on Forever | Section 2.1 | |
| 25 | Banner sound IDs (8959 raid warning, 888 level-up) exist and play on Forever; the larger 40 pt outlined font looks right | `/lp test on`, `/lp sim death Max`, `/lp sim levelup Jo` | **OK (2026-10-11)**: banner and sounds work |
| 24 | `C_EventUtils.IsEventValid` exists. Without it, unknown events could raise errors on registration | No Lua errors on login | No login errors (2026-10-11). Existence not checked separately |
| 26 | Post-hook on `JumpOrAscendStart` (protected) causes no blocked action; `IsFalling()` is still false right after a ground jump | Section 2.6, jump around with debug on | |
| 27 | Hearthstone spell ID 8690; food/drink detected via the names of spells 433 ("Food") and 430 ("Drink") | Section 2.6 | |
| 28 | `TakeTaxiNode`, `TaxiNodeName` exist (flight + flight cost) | Section 2.6 | |
| 29 | `RepairAllItems` post-hook (repair source); vendor sell/buy classified by the open merchant window | Section 2.6 | |
| 30 | `TakeInboxMoney`/`AutoLootMailItem` post-hooks; `GetInboxInvoiceInfo(index)` still returns "seller" in the post-hook (AH mail) | Section 2.6 | |
| 31 | Coin loot money arrives within 2 s of `LOOT_CLOSED` (window grace) | Section 2.6 | |
| 32 | Loot strings `LOOT_ITEM_SELF(_MULTIPLE)`, `LOOT_ITEM_PUSHED_SELF(_MULTIPLE)`, `LOOT_ITEM_CREATED_SELF(_MULTIPLE)` match; `C_Item.GetItemQualityByID(link)` works | Section 2.6 | |
| 33 | `GetLootSourceInfo(1)` gives "GameObject-..." for herb/ore nodes; `IsFishingLoot` exists | Section 2.6 | |
| 34 | `SKILL_RANK_UP` + `CHAT_MSG_SKILL`; `GetProfessions`/`GetProfessionInfo` exist (profession flag) | Section 2.6 | Skill-up messages exist (Defense skill-up seen 2026-10-11) |
| 35 | `DUEL_WINNER_KNOCKOUT`/`DUEL_WINNER_RETREAT` with positional arguments; names without realm for the same realm | Section 2.6 | |
| 36 | `PVP_MATCH_COMPLETE` winner is a faction index (0 Horde / 1 Alliance); `C_PvP.GetScoreInfo` readable after the match | Section 2.6 | |
| 37 | `UnitHonor`/`UnitHonorLevel` and `HONOR_XP_UPDATE` exist on Forever (or Forever uses classic honor ranks) | Section 2.6 | |
| 38 | `C_FriendList.GetFriendInfo(name).connected` for "friends online" | Tooltip while a friend (on your friends list) is online but not grouped | |
| 39 | Settings panel: `RegisterVerticalLayoutCategory`, proxy settings, sliders with formatter, buttons, section headers render | Section 2.6 | |
| 40 | LibDBIcon v12.1.1 works on Forever (button, drag, tooltip); compartment entry via `.toc` fields appears once | Section 2.6 | |
| 41 | Window widgets: `BackdropTemplate`, `UIPanelCloseButton`, gold coin texture `Interface\MoneyFrame\UI-GoldIcon`, fonts; layout fits without overlap | Section 2.6 | |
| 42 | Played time per level from our session timer is close to `/played` | Level up once with the addon running from the start of the level | |
| 43 | STATS sync between two clients (about 2 chunks, BULK priority) arrives; leaderboard shows the friend; offline after relog | Section 2.6 / 3 | |
| 44 | `StaticPopupDialogs`/`StaticPopup_Show` confirmation dialog works | Section 2.6 (reset my stats) | |
