# Testing LooserPiml

There are three levels:

1. **Offline** (busted). Runs on every change and in CI.
2. **In-game solo** with one account: test mode, simulations and `/lp selftest`.
3. **Two players**: you and one friend, first not grouped, then in a dungeon.

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

The mock server behaves like the real one where the communication rule is
concerned: a whisper reaches only an online player, and whispering anyone
else puts "No player named ..." into the sender's chat. Every test checks
**every single `SendAddonMessage` call** of every client: it must be a
WHISPER (never PARTY/RAID/INSTANCE_CHAT), to a name on the sender's
LooserPiml friends list at that moment, and nothing at all may be sent in
test mode. Any "No player named" line fails the test too. `H.friends`
builds connected friends who are **not grouped** (the normal case),
`H.group` friends in a party.

Covered:

| Area | Spec |
|---|---|
| Loading in .toc order, lifecycle, module enable/disable, DB migrations, event isolation, blocked-action logging, slash commands, self-test (echo from a connected friend, multi-chunk, no friend connected, timeout, lockdown), secret values from Roster/encounter APIs | `core_spec.lua` |
| Serialize/compress roundtrip (all byte values), multi-chunk transport between two clients (WHISPER), whispers also in a raid and "nobody" without friends online, echo/duplicate/protocol filtering, hold queue + flush around encounters and lockdown, retry of refused sends, give-up, stale drop, queue cap, test-mode loopback | `comm_spec.lua` |
| Version parse/compare, login handshake, outdated/newer warnings (once), HELLO reply rules, greeting only listed friends who come online (whisper each, cooldown), protocol mismatch, dev builds, fake friends' versions | `version_spec.lua` |
| Friends list: name parsing, add/remove/persist, Friends tab (add by name, add from group without fake friends, add from the WoW friends list with online first and class colors, remove), settings page, `/lp friends`, empty-list hint once after login (not on group join). Communication rule: two connected friends who are **not grouped** exchange stats and ticker events; a party/raid with a stranger gets zero messages to the stranger and nothing on PARTY/RAID; nothing reaches a non-listed player in any code path (ticker, stats, version check, encounter queue flush, roster join, friends list update, self-test); messages from non-listed senders are dropped; removing a friend stops all traffic at once (held messages included); one-sided friends get only the handshake; whispers only to friends online (offline → handshake forgotten, fresh handshake on return); no whispers to offline group members; test mode never sends | `friends_spec.lua` |
| Stats counting, test events excluded from all-time, ranking, Death King report, persistence across reload | `stats_spec.lua` |
| Death/level-up/enter/leave detection, duplicate deaths, drowning (incl. event order, secret values), corpse runs, receiving + sanitizing, encounter hold + "During the boss", `/lp sim` → loopback → receive → stats → display, two-client end-to-end, banner sound, "Ticker messages from friends" Banner / Chat line only / Off (incl. during a boss), combined banner for friends entering the same dungeon | `ticker_spec.lua` |
| Localized format strings → patterns (positional args, secret text), money/duration formatting | `util_spec.lua` |
| Gaming day/week periods (06:00 boundary), aggregation per event type, merge, rollup + cap without changing totals, aggregation per period, sanitizing received aggregates | `stats_model_spec.lua` |
| Recording per event type with mocked events: death, level-up (played time), quests, instances, boss kills/wipes, money sources (merchant, repair, loot grace, mail, AH mail, flight, quest), travel, jumps, food/drink, group time with friends, rare loot, crafting, gathering (herb, ore, skinning, fishing), chests separately (quest objects excluded, secret casts not guessed), skill-ups, duels, battlegrounds, honor; collect off; compaction; simulated events never recorded | `stats_collect_spec.lua` |
| Sync: exchange after the handshake and on changes, ≤ 1 broadcast per 30 s, share off = nothing sent, staleness of tonight/week, cache survives reload (offline friends), hostile payloads, boss-fight queue with newest snapshot only, message size, sample friends (never on the real list) | `stats_sync_spec.lua` |
| Awards incl. ties and empty data, ranking rows and bar fractions, formatting, ranking with real synced data | `leaderboard_spec.lua` |
| Option defaults, v0.1.0 → v0.2.0 migration, ticker filters, own events, boss recap, banner time/size/move/reset, Blizzard panel build with live proxy values, the friends dropdown, reset confirmation, testing buttons | `options_spec.lua` |
| Inventory: bag counts (debounced), bank only while open (snapshot + time), unreadable/secret slots skipped; full snapshot after the handshake and deltas ≤ 1 per 30 s between friends who are not grouped; bank time and gold synced and cached for offline friends; sharing switches (nothing of that kind sent, receivers drop the cache); INVREQ when a delta doesn't fit; hostile payloads; snapshot size. Tab: sort by total, holder chips with bank tag, search as you type, category and location filters, async loading of uncached names, empty-result hint, gold bar (non-sharers left out, stale marker, total), last updated column, no messaging button | `inventory_spec.lua` |
| Wishlist: add by name / link / ID, quantity validation, remove; shift-click link into the box (post-hook); sync to friends who are not grouped; received lists stored under the sender only and never editable; "N among friends" (green), "looted tonight", "no friend has it yet"; wishlist loot banner (own wish, friend's wish), banner toggle, chat-line-only mode, unrelated loot ignored | `wishlist_spec.lua` |
| Profiles: sections mapping incl. "—" for missing fields (older friends), extras synced between friends who are not grouped, hostile extras, "first to die in a dungeon", played time counted quietly, tab list + selection | `profiles_spec.lua` |
| Tonight: KPIs and timeline with friends who are not grouped, 06:00 boundary, timeline across reload, 7-day pruning, evening recap once per evening (local only), recap off, no recap after an empty evening | `tonight_spec.lua` |
| Ranked duel handshake between friends who are not grouped: panel on both sides (below the game's dialog for the challenged player), both Ranked → ranked (shared duel id, records on both sides), one Fun → not ranked, no answer → not ranked, fled = loss, streak per opponent, decline closes both panels and drops the choice, choice expires after the duel ends, the challenger's panel opens from the friend's ask if the hook missed it, non-friend or offline opponent → no panel and no message, the choice goes only to the opponent (whisper), "Ask ranked?" off, `/lp sim duel`; **no duel action (StartDuel/AcceptDuel/CancelDuel/ForfeitDuel) is ever called by LooserPiml and Blizzard's dialog is never hidden or clicked** (also checked after every spec) | `duels_spec.lua` |
| Ladder: merge of both sides (confirmed, disputed, one-sided), sort by wins then win rate, streaks, head to head matrix Ranked / All duels (incl. a friend without duel data), sync between three friends who are not grouped, disputed duel left out, only listed opponents sent, hostile payloads, STATS size with 60 ranked duels, sample duels | `ladder_spec.lua` |
| Ranked duel banner to all connected friends (one per duel, the loser sends nothing), "fled" text, fun duels as chat line only (setting, default off), "Ranked duel results" off, sanitizing, `/lp sim duel` banner; PvP tab ladder/matrix/toggle/placeholder/empty hints, tab order; the three duel settings and defaults; Duel King per period (`leaderboard_spec.lua`) | `pvp_spec.lua` |
| Window open/ESC/toggle/position, tabs (Leaderboard first, Friends last), leaderboard contents and selectors, minimap button clicks, tooltip lines, minimap hide/show, Addon Compartment callbacks, footer version status | `window_spec.lua` |

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
  - Without a connected LooserPiml friend: `[INFO] Real transport: not tested, no LooserPiml friend is connected right now`. That's expected: the Forever server rejects whispers to yourself ("No player named X is currently playing"), so there is no solo transport test.
  - With a connected friend (grouped or not): `[OK] Real transport: echo from <friend> received after X s, payload intact`. This whispers a multi-chunk message to the friend, whose LooserPiml whispers it back.
  - In test mode: `[INFO] ... not tested in test mode` (nothing leaves the client in test mode).
- [ ] If the echo times out, note the exact message; check section 3 as well.

### 2.3 Test mode + simulations

- [ ] `/lp test on`. The message lists Max, Lena, Jo and Kim. About 1 s later: "Kim runs an older LooserPiml (...)" and "Jo has a newer LooserPiml (...)".
- [ ] `/lp version` lists the fake friends with their versions.
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
- [ ] Window: title "LooserPiml · Friends", tabs Leaderboard and Friends, close button, ESC closes it, it can be dragged and stays where it was after `/reload`. Colors look like the mockup (dark brown, bronze borders, gold headings), text is readable.
- [ ] `/lp test on`, then Settings › Testing › "Fill with sample friends": the leaderboard shows four sample friends; period buttons (Tonight / This week / All time) and metric buttons (Deaths / Gold / Quests / Level-ups) switch the content; bars look right; names are class-colored.
- [ ] **Gold**: the Gold Hoarder card shows the most gold on hand with "… right now" (Kim, who doesn't share gold in the sample, never wins it). Metric "Gold": the note "gold on hand right now (the period does not apply)" appears next to Ranking, Kim is not listed, and switching Tonight / This week / All time doesn't change the gold rows (only the other cards).
- [ ] Your own gold: the value in the Gold ranking matches your bag gold. Settings › Stats › "Share my gold" off: you disappear from the Gold ranking and can't win Gold Hoarder; on again: you're back.
- [ ] Solo without test mode: the cards say "No one yet" (or show you), with the hint to add friends in the Friends tab.

**Settings (Esc › Options › AddOns › LooserPiml)**
- [ ] The category exists with the sections LooserPiml friends, Ticker messages, Banner, Stats, Minimap, Testing, and a subpage **Friends** (see 2.7).
- [ ] Each Ticker checkbox hides its message type (try with `/lp sim ...` in test mode); "Also show my own events" off hides only your own.
- [ ] "Ticker messages from friends" is a dropdown with Banner / Chat line only / Off. With `/lp sim death Max` in test mode: Banner shows the banner, Chat line only prints just the chat line (no banner, no sound), Off shows nothing. Your own `/lp sim death` is not affected.
- [ ] Banner: display time and size sliders change the next banner; "Unlock / lock" shows a sample banner you can drag, locking makes it click-through again; "Reset banner position" puts it back. Position is kept after `/reload`.
- [ ] Stats: "Reset my stats" asks for confirmation first; "No" keeps everything.
- [ ] Minimap: unticking hides the button, ticking shows it again.
- [ ] Testing buttons work (simulate death / level up / boss fight, sample friends, self-test, debug log).

**Stats collection** (with `/lp debug on`: each recorded event logs "Stats: <type> recorded"; check with `/lp log 30`)
- [ ] Death, level-up (`played` close to `/played` for that level), quest turn-in (with XP and money).
- [ ] Gold: loot coins from a mob (`loot`), sell and buy at a vendor (`vendor_sell` / `vendor_buy`), "Repair all" (`repair`), take gold from a normal mail (`mail`) and from an auction house sale (`ah_mail`), pay a trainer (`trainer`), take a flight (`flight`).
- [ ] Loot a blue/purple item: `loot_rare` with the right quality. Grey/white/green items are not recorded.
- [ ] Craft something (`profession` crafted), gather a herb and an ore node and skin a mob (`gathered`, source herb / mining / skinning), fish (`gathered`, source fishing), get a skill-up (`skillup`; for a profession `profession = true`, for weapon/defense skills `false`).
- [ ] Open a chest: **not** recorded as gathered; no log line (it's a counter): check `/dump LooserPimlDB.modules.Stats.chars` → today's bucket has `chestsOpened`. Picking up a quest object from the ground (only quest items in the loot) does not count.
- [ ] New subzone, flight path, hearthstone are recorded; jumping counts only real jumps (not swimming up or pressing in mid-air); eating and drinking are counted.
- [ ] Duel a friend: win, lose and flee once each; only your own duels are recorded, with the opponent's name.
- [ ] Battleground: joined, finished (won/lost, your killing blows etc.), and leaving early counts as deserted. Honor snapshot after honor changes.
- [ ] No `[Blocked action]` / `[Forbidden action]` line for LooserPiml during any of this, especially while jumping (post-hook on a protected function).

**Sync** (with a friend, see section 3; you both have to add each other first, see 2.7)
- [ ] After both added each other, the friend appears on your leaderboard within about 10 s; changes arrive within about 30 s.
- [ ] After the friend logs out and you `/reload`, they are still listed, marked offline.
- [ ] Settings › Stats › "Share my stats" off on one side: the other side stops receiving updates.
- [ ] Gold: the friend picks up or spends gold; within about 30 s your Gold ranking shows their new amount, and Gold Hoarder goes to whoever has more right now (not who looted more). The friend turns "Share my gold" off: within about 30 s they are gone from the Gold ranking and the Gold Hoarder card, but still listed everywhere else.

### 2.7 LooserPiml friends and the communication rule

LooserPiml only talks to players on your LooserPiml friends list who added
you too, grouped or not. Nobody else may receive anything from it, not even
hidden addon messages. Everything with a friend is in section 3.

**Solo**
- [ ] Right after login with an empty list: one chat line "Your LooserPiml friends list is empty ...". Joining a group later doesn't repeat it.
- [ ] Minimap button › window › tab **Friends**: explanation text, "Add by name", "Add from group", "Add from WoW friends" (with the hint to be WoW friends too), "Your list (0/40)", "Nobody yet".
- [ ] "Add from WoW friends" shows your WoW friends who aren't listed yet, online ones first (offline ones grey). Clicking one adds them.
- [ ] Type a name and press Enter or "Add": it appears in the list with its class color if known, status "offline (or not on your WoW friends list)". "Remove" takes it off again.
- [ ] Invalid input ("123", "a b") shows "That is not a character name"; your own name shows "That is you"; a second add shows "already on your list".
- [ ] Esc › Options › AddOns › LooserPiml: section "LooserPiml friends" with a "Manage" button that opens the subpage **Friends** (same list, same buttons). Typing in its edit box works (no key bindings fire while typing); Esc leaves the box.
- [ ] `/reload`: the list is still there.
- [ ] Test mode on: the fake friends (Max, Lena, Jo, Kim) are **not** offered under "Add from group".

**In a group with strangers** (anyone not on your list, e.g. a random group)
- [ ] `/lp debug on`, die once: the debug log has nothing about sending (no "Holding"/"Flushed"), unless a listed friend is online somewhere.
- [ ] Nothing is ever sent on the group channel: if a stranger in the group runs LooserPiml with `/lp debug on`, their `/lp log` shows nothing from you.

---

### 2.8 Stage B: inventory, wishlist, profiles, tonight (solo)

**Inventory** (with `/lp debug on`)
- [ ] Tab **Inventory**: title "Friends' inventory", subtitle "Bags and banks of your LooserPiml friends, updated automatically", views Items / Wishlists.
- [ ] `/lp test on`, Settings › Testing › "Fill with sample friends": gold bar with Lena, Max, Jo (not Kim) and a total; rows sorted by total; holder chips with a grey "bank" tag; "Last updated" shows "bags now · bank 3 days ago" and one "offline · last seen ...". 📸
- [ ] Type "leather" in the search box: the list filters while typing. Materials / Consumables / Gear and Bags + bank / Bags / Bank switch the rows. A search with no result shows "None of your friends has this yet ..." with "+ Add to my wishlist".
- [ ] Your own bags: loot or move something; within a few seconds your own counts in the tab change. Open the bank: your bank items appear (as yours, with the bank tag); after closing they stay.
- [ ] An item you never saw before (from a friend, later) shows "Loading ..." for a moment and then its name.

**Wishlist**
- [ ] Wishlists view: type "Linen Cloth" (or any item you have) + quantity → "+ Add to my wishlist". Shift-click an item in your bags while the box has focus: its link goes into the box. 📸
- [ ] Your entry shows "for you" and a Remove button; sample friends' entries ("for Lena", "for Jo") have no Remove button.
- [ ] `/lp sim wishloot Max`: banner "Max looted Medium Leather ×3 · On Lena's wishlist · 7 still needed" (test mode).
- [ ] Settings › Inventory › "Banner when a wishlist item is looted" off: the sim shows nothing.

**Profiles**
- [ ] Tab **Profiles**: you first with your level; clicking a sample friend switches the right side. Sections Progress, Deaths, Loot & gold, Professions, Travel, PvP, Social; "—" where there is no data. Your own professions and favourite zone appear. 📸

**Tonight**
- [ ] Tab **Tonight**: awards card, five tiles (Session, Deaths, Level-ups, Gold looted, Duels), timeline with your real events of tonight (time, icon, text), newest at the bottom. `/reload`: the timeline is still there.
- [ ] Next day (first login after 06:00): a small window "Last evening (...)" with last evening's awards and totals, once; not again after `/reload`. Settings › Stats › "Show evening recap" off: no window. 📸

**Gold**
- [ ] Leaderboard › Gold: rows read "71g 60s right now"; Gold Hoarder card with "right now".

### 2.9 Stage C1: ranked duels (solo)

- [ ] `/lp test on`, `/lp sim duel Max ranked`: a small panel "LooserPiml · ranked duel?" appears above the screen center with "[test] Your ranked record against Max: 0 – 0", buttons **Ranked** and **Just for fun**, the note "Counts as ranked only if both pick Ranked. …" and the status "Nobody picked yet." About 1 s later: "Max picked Ranked · your turn." 📸
- [ ] Click **Ranked**: the button turns bronze, status "You both picked Ranked: this duel counts!". After about 8 s the panel closes; after 10 s a banner "[test] … <you> won a ranked duel against Max · Ranked head to head: <you> 1 – 0 Max". 📸
- [ ] `/lp sim duel Lena fun`: Lena picks Just for fun ("Lena picked Just for fun · …"); no banner at the end. Settings › Ticker messages › "Fun duel results" on and again: a chat line "… beat Lena in a duel (just for fun)", still no banner.
- [ ] `/lp sim duel Jo fled`: the banner ends with "(Jo fled)".
- [ ] The panel's buttons do nothing else: no duel request, no dialog, nothing in chat. No `[Blocked action]` line.
- [ ] Settings › Testing › "Fill with sample friends", then the **PvP** tab: subtitle "Duels between LooserPiml friends", ladder #1 Max 6 / 3 / 67 % / W3 … #4 Kim; head to head matrix with "—" on the diagonal, highlighted high values and a "W – L" column; "Ranked" / "All duels" switch the numbers; "Battlegrounds – coming later" at the bottom. 📸
- [ ] Leaderboard: a fifth card **Duel King** (Max with sample friends, "All time"). Profiles › PvP: "Ranked duels won / lost", "All duels won / lost".
- [ ] Settings › Ticker messages: "Ranked duel results" (on), "Fun duel results" (off), "Ask "ranked?" when dueling a LooserPiml friend" (on).
- [ ] A duel with a stranger (anyone not on your list): no panel at all; the duel is recorded as a normal duel (`/lp debug on`: "Stats: duel recorded").

## 3. Two players: you and one friend (about 60 minutes)

Order: install, add each other, **not grouped first** (that's the normal
case), then grouped in a dungeon (boss queue). Both `/lp debug on`.

**Screenshots** (Print Screen in WoW, files land in
`<WoW>\_classic_beta_\Screenshots`; or Win+Shift+S). Take the ones marked
📸 and send them to me together with anything that looks wrong.

### 3.1 Install the beta (both, 5 min)
- [ ] Your friend installs **v0.2.0-beta.3** as described in the README ("Beta versions"): WowUp › Options › WoW: Forever › Default Addon Channel = **Beta**, then Get Addons › Install from URL. Fallback: the zip from the release marked "Pre-release".
- [ ] You either use the same beta or stay on the dev junction (`dev`). With `dev`, version warnings don't appear (dev builds are never compared); that's correct.
- [ ] In-game, character select › AddOns: LooserPiml is listed and enabled (tick "Load out of date AddOns" if needed). No Lua error on login.
- [ ] `/lp version` on the friend's side shows `v0.2.0-beta.3`. 📸 WowUp's addon list with the version, and the `/lp version` line.

### 3.2 Add each other (both, 5 min)
- [ ] **WoW friends**: Social (O) › Add Friend, in both directions. Each sees the other as online.
- [ ] **LooserPiml friends**: minimap button › Friends › "Add from WoW friends" (or by name). As long as only one side added the other, the status says "online, waiting for them to add you".
- [ ] When both added each other: within about 5–10 s both lists say **connected**, and `/lp version` shows the other's version (or `dev`). 📸 the Friends tab on both sides.

### 3.3 Not grouped (15 min): ideally in different zones
- [ ] `/lp selftest` on your side: `[OK] Real transport: echo from <friend> received after X s, payload intact`. 📸 the self-test lines (and copy the `[INFO] Client APIs` line into STATUS.md).
- [ ] **Ticker**: the friend dies (fall damage works). You get the banner with their class color plus the chat line; they see their own banner once, not twice. If one of you levels up, the other gets "reached level N!". 📸 the banner on your side.
- [ ] **Setting**: Options › AddOns › LooserPiml › "Ticker messages from friends" = "Chat line only": the next death of the friend shows only a chat line, no banner, no sound. "Off": nothing at all. Back to "Banner".
- [ ] **Stats**: within about 30 s the friend's deaths are on your leaderboard (minimap button › Leaderboard, Tonight); the minimap tooltip says "Friends online with LooserPiml: 1". 📸 the leaderboard.
- [ ] **Offline display**: the friend logs out. Within a few seconds their status is "offline", the leaderboard still lists them with "(offline)" and their last values. They log back in: "connected" again within about 10 s. 📸 the leaderboard row with "(offline)".
- [ ] **Remove friend**: you remove them in the Friends tab. Their next death: no banner, no chat line for you. Your next death: they get nothing. Add them again: "connected" again within a few seconds.
- [ ] At no time a "No player named ... is currently playing" line in chat.

### 3.3b Inventory, wishlist, profiles, tonight, still not grouped (15 min)
- [ ] **Inventory**: within about 10 s after "connected" your friend's bags appear in your Inventory tab (and yours in theirs); their gold is in the gold bar. They loot something: their count changes within about 30 s. 📸 your Inventory tab with their chips.
- [ ] **Bank**: your friend opens their bank: "bank now" in your "Last updated" column, their bank items with the "bank" tag. They close it and log out: "offline · last seen ..." and their items stay listed. 📸
- [ ] **Sharing off**: your friend turns off "Share my bags and bank": within a few seconds their items vanish from your tab (gold stays). "Share my gold" off: they leave the gold bar, the Gold ranking and Gold Hoarder. Both on again: everything is back.
- [ ] **Wishlist**: you add an item your friend can loot (e.g. Linen Cloth ×20). Within about 10 s they see "for <you>" in their Wishlists view, without a Remove button. They loot that item: you get the banner "<friend> looted Linen Cloth ×N · On your wishlist · M still needed", they see "On <you>'s wishlist". 📸 the banner.
- [ ] Your wishlist entry then shows "N looted tonight" (and "N among friends").
- [ ] **Profiles**: your friend's profile shows their level, professions, deaths and travel; fields their client doesn't have yet show "—". 📸
- [ ] **Tonight**: the timeline lists their deaths and level-ups too; the Deaths tile counts both of you.

### 3.4 Grouped in a dungeon (15 min)
- [ ] Group up (the Friends tab still says connected; nothing changes about the messages, they stay whispers).
- [ ] Enter the dungeon together: within about 2 s **one** banner "<You> and <friend> entered <dungeon>." on both sides (each sees their own name in the list). 📸
- [ ] Before the first pull, inside the dungeon: `/dump C_ChatInfo.InChatMessagingLockdown()`. Note the result (TODO #7).
- [ ] **Boss queue**: one of you dies during a boss fight (or note any death during one). Nobody gets a banner during the fight. After the kill or wipe, both see "During the boss: X died." within a few seconds. 📸
- [ ] Debug log (`/lp log 30`) on the dying player's side: "Holding TICK message (encounter)", later "Flushed". If you can, `/dump C_ChatInfo.InChatMessagingLockdown()` during the fight (macro it before the pull; TODO #6).
- [ ] Leave the dungeon together: one combined "left" banner.

### 3.5 Ranked duels (15 min, not grouped)

Duel each other out in the open world (no group needed). One of you is
the **challenger** (unit menu › Duel, or `/duel` with the friend
targeted), the other the **challenged** (gets the game's dialog).

- [ ] **Both Ranked**: challenge. The challenged sees the game's duel dialog and the LooserPiml panel **right below it**; the challenger sees the panel near the screen center. Both: "Your ranked record against <friend>: 0 – 0". Both click Ranked: "You both picked Ranked: this duel counts!" on both sides. 📸 both screens with the panel (the challenged one with the game's dialog).
- [ ] The challenged accepts **in the game's dialog**. Both panels stay for the countdown (about 3 s) and then close. LooserPiml never accepted, declined or closed the game's dialog on its own.
- [ ] Fight it out. The winner sees "<winner> won a ranked duel against <loser> · Ranked head to head: <winner> 1 – 0 <loser>", the loser sees the same banner. 📸 the banner.
- [ ] Within about 30 s: PvP tab on both sides shows the duel on the ladder (1 – 0 / 0 – 1, W1 / L1) and a 1 in the matrix; Profiles › PvP "Ranked duels won / lost" 1 / 0. Leaderboard › Tonight: Duel King = the winner. 📸 the PvP tab.
- [ ] **One Fun**: next duel, one picks Ranked, the other Just for fun: "… picked Just for fun · this duel doesn't count for the ladder." No banner after the duel (unless "Fun duel results" is on: chat line only). Ladder unchanged; "All duels" in the matrix goes up.
- [ ] **Flee**: a ranked duel where one of you runs out of the duel area until the game ends it: the banner says "(<loser> fled)", the one who fled gets the loss on the ladder.
- [ ] **Decline**: challenge again, both pick Ranked, the challenged clicks **Decline** in the game's dialog: both panels close at once. Then a duel without picking anything: just for fun, nothing on the ladder.
- [ ] **No answer**: only the challenger picks Ranked, the challenged picks nothing and accepts: not ranked.
- [ ] Settings › "Ask "ranked?" when dueling a LooserPiml friend" off on one side: that side sees no panel; the other side's panel says "<name> doesn't ask for ranked duels · just for fun." On again.
- [ ] `/lp log 30` on both sides: "Duel with … closed (result)" after each duel, no `[warn]`, no `blocked`/`forbidden`. Note the order of `DUEL_FINISHED` and the result line if you see it (TODO #65).

### 3.6 Afterwards
- [ ] `/lp log 50` on both sides. Look for `[warn]`, `[error]`, `blocked`, `forbidden`. 📸 if there is anything.
- [ ] Send me the screenshots, the self-test lines and anything odd; I'll write the results into STATUS.md.

---

## TODO(verify in-game): open items

| # | What | How to check | Result |
|---|---|---|---|
| 1 | Interface number is 16001 and stays that at launch (Nov 4, 2026) | `/dump select(4, GetBuildInfo())` | **16001 confirmed on the beta (2026-10-11)**. Launch value still open |
| 2 | Client folder name `_classic_beta_` (beta). Launch name? | Look in the WoW folder after launch | |
| 3 | LibStub, CallbackHandler, AceComm r14 + ChatThrottleLib v32, AceSerializer, LibDeflate load on Forever | `/lp selftest` step 1, no Lua errors | **OK (2026-10-11)**: CallbackHandler r8, AceComm r14, AceSerializer r5, LibDeflate r3 loaded, roundtrip OK |
| 4 | Addon whisper to yourself (incl. multi-chunk) is delivered | `/lp selftest` | **No (2026-10-11)**: server answers "No player named 'X' is currently playing" per chunk. The self-test now pings a connected friend, who echoes it (see #5) |
| 5 | WHISPER addon messages arrive between friends who are not grouped (incl. multi-chunk) | Section 3.3 (self-test, ticker, stats) | |
| 6 | During boss encounters: `InChatMessagingLockdown()` is true and/or sends return `AddOnMessageLockdown` (11); messages sent then are dropped, not delayed by the server | Section 3.4, debug log ("refused by the client") | |
| 7 | Are regular dungeons (outside encounters) a "communication-restricted map"? If yes, all dungeon messages are delayed until you leave | `/dump C_ChatInfo.InChatMessagingLockdown()` inside a dungeon | |
| 8 | `ADDON_RESTRICTION_STATE_CHANGED` exists on Forever and fires Inactive (0) when restrictions end | `/lp selftest` APIs line (`RestrictionEvent=`), debug log | Event exists (2026-10-11). Firing on lift: still open |
| 9 | `ENCOUNTER_START`/`ENCOUNTER_END` fire for 5-man bosses on Forever; `C_InstanceEncounter.IsEncounterInProgress` exists | Section 3.4, selftest APIs line | API exists (2026-10-11). Events in a real boss: still open |
| 10 | `CHAT_MSG_ADDON` payloads are never secret, even while locked down. AceComm doesn't check, so this would show as AceComm Lua errors during bosses | BugSack during section 3.4 | |
| 11 | `PLAYER_DEAD` fires once per death; not on login as a ghost | Section 2.4 | **OK (2026-10-11)**: one message per death, "Again" variant on the second death |
| 12 | Drowning: `MIRROR_TIMER_START` BREATH payload (value in ms, scale -1) is not secret; order of `MIRROR_TIMER_STOP` vs `PLAYER_DEAD`; `GetMirrorTimerProgress("BREATH")` at empty breath | Section 2.4 with debug on | |
| 13 | `PLAYER_LEVEL_UP` level argument is a plain number | Section 2.4 | **OK (2026-10-11)**: level-up banner with the correct level |
| 14 | `GetInstanceInfo()` instanceType `party`/`raid` and a stable instanceID on Forever | Section 2.4 | |
| 15 | `UnitName`/`UnitClass` of group members are not secret out of combat (class colors work) | Section 3.4 | |
| 16 | Raid target icon textures and `GameFontNormalHuge` exist and look fine | Section 2.3 | **OK (2026-10-11)**: icon and banner render |
| 17 | SavedVariables persist (an early beta build had a restore bug) | Section 2.1 | |
| 18 | ~~`INSTANCE_CHAT` in dungeon-finder groups~~ | Obsolete since 2026-10-12: group channels are never used | |
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
| 33 | `GetLootSourceInfo(1)` gives "GameObject-..." for chests; `IsFishingLoot` exists | Section 2.6 | |
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
| 45 | Gathering casts: spells 2366 "Herb Gathering", 2575 "Mining", 8613 "Skinning" exist; gathering fires `UNIT_SPELLCAST_SUCCEEDED` (not secret) shortly before `LOOT_OPENED`; `GetNumLootItems`/`GetLootSlotInfo` (7th return `isQuestItem`) work | Section 2.6 (gathering, chests) | |
| 46 | The whisper target "Name" (without realm) works for the own realm; AceComm reports the sender of a whisper as "Name" | Section 3.3 | |
| 47 | `UnitIsConnected` reports offline group members; `UNIT_CONNECTION` fires when they go offline/come back | A friend logs out while grouped: no "No player named" line on your side | |
| 48 | `FRIENDLIST_UPDATE` fires when a character friend logs in/out; `C_FriendList.GetFriendInfo("Name")` works for the own realm | Section 2.7 (not grouped, on each other's friends list) | |
| 49 | Settings subpage via `Settings.RegisterCanvasLayoutSubcategory` renders; `Settings.OpenToCategory(subcategory:GetID())` opens it; plain `EditBox` + `BackdropTemplate` takes typing | Section 2.7 (solo) | |
| 50 | Cross-realm friends ("Name-Realm") on Forever: whisper and friends-list lookup work, if Forever has connected realms at all | Only if a friend plays on another realm | |
| 51 | Nothing reaches a player who isn't on the list: a non-listed LooserPiml user in the group receives nothing (their debug log stays silent about you) | Section 2.7 (stranger with LooserPiml) | |
| 52 | `C_FriendList.GetNumFriends`/`GetFriendInfoByIndex` list the character friends; `LOCALIZED_CLASS_NAMES_MALE/FEMALE` exist (class colors in "Add from WoW friends") | Section 2.7 | |
| 53 | `Settings.CreateDropdown` with `Settings.CreateControlTextContainer` renders the "Ticker messages from friends" dropdown and saves the choice | Section 2.6 | |
| 55 | Bag and bank containers as in `Enum.BagIndex` (backpack 0, bags 1-4, reagent bag 5, `Characterbanktab` -2, `CharacterBankTab_1-9` 6-14) are readable with `C_Container`; the bank reads only while open; `BAG_UPDATE_DELAYED` and `PLAYERBANKSLOTS_CHANGED` fire | Section 2.8 (own bags and bank) | |
| 56 | `C_Item.GetItemNameByID`, `GetItemQualityByID`, `GetItemInfoInstant` (class, icon, type name) and `Item:CreateFromItemID():ContinueOnItemLoad` work; uncached names arrive | Section 2.8 / 3.3b | |
| 57 | Shift-clicking an item puts its link into the wishlist box (post-hook on `ChatFrameUtil.InsertLink` or `ChatEdit_InsertLink`) | Section 2.8 (wishlist) | |
| 58 | `C_Item.GetItemInfoInstant("Item Name")` resolves names of cached items (typing a wishlist item) | Section 2.8 (wishlist) | |
| 59 | Inventory traffic between friends: full snapshot after "connected", deltas within ~30 s, no "No player named" lines, no throttling problems | Section 3.3b | |
| 60 | Inside a dungeon, a friend's death message names the instance as its zone (for "first to die in a dungeon") | Section 3.4 | |
| 61 | `GetProfessions`/`GetProfessionInfo` return name and skill level (profile professions) | Section 2.8 (profiles) | |
| 62 | The evening recap window appears on the first login after 06:00 and only once | Section 2.8 (tonight, next day) | |
| 63 | `DUEL_REQUESTED` fires on the challenged side with the challenger's name ("Name" on the own realm), not secret | Section 3.5 (panel opens on the challenged side) | |
| 64 | Post-hooks on `StartDuel` (unit menu "Duel", `/duel`; argument unit token or name), `AcceptDuel` and `CancelDuel` (dialog buttons) fire and cause no blocked action | Section 3.5 (challenger's panel opens at once, not only after the friend's ask; panels close on accept/decline) | |
| 65 | `DUEL_FINISHED` fires on decline, withdraw, timeout and after the duel; it comes within 5 s of the result line (`RESULT_GRACE`), in either order | Section 3.5, debug log | |
| 66 | The duel countdown after accepting is about 3 s (`Duels.COUNTDOWN`, panel close) | Section 3.5 | |
| 67 | `StaticPopup_FindVisible("DUEL_REQUESTED")` returns the game's duel dialog and our panel can be anchored below it | Section 3.5 (panel right below the dialog) | |
| 68 | The game withdraws an unanswered duel request by itself (with `DUEL_FINISHED`); our 120 s safety net is never needed | Section 3.5 (let a request run out once) | |
| 69 | Raid target icons 7 (cross) and 5 (moon) render in the duel banner / chat line | Section 2.9 | |
| 54 | The GitHub release of a `-beta` tag is marked "Pre-release", and WowUp with Default Addon Channel = Beta installs it from the URL (with Stable it picks v0.1.0) | Section 3.1 | Release marking checked on GitHub (see STATUS.md); WowUp still open |
