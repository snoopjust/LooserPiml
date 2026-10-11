# Architecture

How LooserPiml is put together. Keep this file current when files, load
order, message flow or restriction handling change (see CLAUDE.md).

## The idea in one paragraph

Every client watches only **its own** player (death, level up, dungeon). It
shows the event locally right away, counts it, and broadcasts it as a hidden
addon message to the group. Friends' clients receive it, check it, count it
and show it. Nobody ever inspects other players, so no secret unit data is
needed. While the game blocks addon messages (boss encounters), outgoing
messages wait in a queue and banners are held. Both come out after the
fight.

```mermaid
flowchart TB
    Ticker["Ticker module<br/>Ticker.lua · Stats.lua · Display.lua"]
    Future["Inventory · Professions · Bets<br/>(planned)"]
    Core["Core services<br/>Events · DB · Log · Roster<br/>Comm · Version · TestMode · Slash"]
    Libs["AceComm-3.0 + ChatThrottleLib<br/>AceSerializer-3.0 · LibDeflate"]
    API[("WoW client API<br/>game events · C_ChatInfo.SendAddonMessage · CHAT_MSG_ADDON")]
    Ticker --> Core
    Future -.-> Core
    Core -->|"Comm only"| Libs
    Core --> API
    Libs --> API
```

Modules never call each other. They only use Core: game events via
`ns.Events`, network via `ns.Comm`, storage via `ns.DB`. That keeps a module
removable.

## Files

### Addon (loaded by the game)

| File | Job | Look at |
|---|---|---|
| `LooserPiml.toc` | Metadata (Interface 16001, version placeholder, SavedVariables) and the **load order** | — |
| `Core/Init.lua` | Creates the shared namespace `ns`, the core-service and module registries, the lifecycle (ADDON_LOADED → `ns:Initialize`, PLAYER_LOGIN → `ns:Enable`), `ns.SafeCall`, `ns.IsSecret` | `RegisterCore`, `NewModule`, `EnableModule`/`DisableModule`, boot frame |
| `Core/Util.lua` | Pure helpers: localized GlobalStrings format → pattern matching (positional args), money/duration formatting, table copy | `MatchFormat`, `FormatMoney` |
| `Locales/enUS.lua` | Every user-visible string in `ns.L`, incl. the Ticker text variants with `{name}`-style tokens | `L.TICKER` |
| `Core/Events.lua` | The single event frame; dispatches game events and internal `LP_*` messages to registered owners; tracks boss-encounter state | `Register`, `dispatch`, `IsEncounterActive`, `SetSimulatedEncounter` |
| `Core/DB.lua` | `LooserPimlDB`: defaults, `schemaVersion`, ordered migrations, per-module storage | `Migrate`, `GetModuleDB` |
| `Core/Log.lua` | Ring buffer + chat output by level; records ADDON_ACTION_BLOCKED/FORBIDDEN, LUA_WARNING, our Lua errors | `IsVerbose`, `CaptureError`, `InstallErrorHook` |
| `Core/Roster.lua` | Group members as `Name-Realm`, class colors, which addon channel reaches the group, fake members for test mode | `Scan`, `Normalize`, `GetChannel`, `ColorName` |
| `Core/PlayerEvents.lua` | Detects the own player's death (incl. drowned), level-up and instance enter/leave (with corpse-run rule) and fires `LP_PLAYER_DEAD`, `LP_PLAYER_LEVEL_UP`, `LP_INSTANCE_ENTER/LEAVE` for any module | `PLAYER_DEAD`, `WasDrowning`, `PLAYER_ENTERING_WORLD`, `GetCurrentInstance` |
| `Core/Comm.lua` | Encoding, sending (hold queue, retries), receiving (filters, dispatch to handlers), test loopback, self-test transport | `Send`, `IsRestricted`, `Hold`, `Flush`, `Transmit`, `Receive` |
| `Core/Version.lua` | HELLO handshake and local version warnings | `SendHello`, `OnHello`, `Check`, `Compare` |
| `Core/TestMode.lua` | `/lp test` (loopback + fake group), simulation registry (`/lp sim`), `/lp selftest` | `Enable`, `Sim`, `SimEncounter`, `SelfTest` |
| `Core/Slash.lua` | `/lp` dispatcher; modules register subcommands | `Register`, `Dispatch` |
| `Modules/Ticker/Ticker.lua` | Creates the Ticker module; turns `LP_PLAYER_*`/`LP_INSTANCE_*` messages into announcements, broadcasts them, receives others' | `OnOwnEvent`, `OnPlayerDead`, `Sanitize`, `OnTick`, `Simulate` |
| `Modules/Ticker/Stats.lua` | Counters per player: session (memory) and all-time (SavedVariables) | `Record`, `Ranking`, `BuildReport` |
| `Modules/Ticker/Display.lua` | Turns an event into text, banner queue, encounter hold, local chat line, banner frame | `Format`, `Compose`, `ShowEvent`, `OnEncounterEnd`, `Render` |
| `Modules/Stats/Stats.lua` | Stats module: per-character event log and daily buckets in SavedVariables, recording, compaction, friends cache | `Record`, `Count`, `GetAggregates` |
| `Modules/Stats/Model.lua` | Pure data model: gaming day/week periods, aggregates per event type, rollup + cap, sanitizing received aggregates | `AddEvent`, `Merge`, `Compact`, `Aggregate`, `Sanitize` |
| `Libs/…` | LibStub, CallbackHandler, AceComm (+ ChatThrottleLib), AceSerializer, LibDeflate. Fetched, not committed | — |

### Development only (not in the release zip)

| File | Job |
|---|---|
| `spec/support/wow_mock.lua` | Simulated game client: its own global environment, clock, timers, frames, events, units, network. Errors on visible chat |
| `spec/support/helpers.lua` | Loads every `.toc` file (libraries included) into a mock client and boots it; builds multi-client groups |
| `spec/*_spec.lua` | busted tests per area (core, comm, version, stats, ticker) |
| `tools/fetch-libs.ps1` | Downloads the pinned libraries into `Libs/` |
| `tools/link-addon.ps1` | Junction `<client>\Interface\AddOns\LooserPiml` → repo |
| `tools/setup-test-env.ps1`, `tools/run-tests.ps1` | Lua 5.1 + busted toolchain, test runner |
| `.pkgmeta`, `.github/workflows/*.yml` | Packager config (libs as externals) and CI: tests on push, release zip on tag `v*` |

## Load order and lifecycle

The game runs the `.toc` files top to bottom, each exactly once, passing
`(addonName, ns)`. That's the `local ADDON_NAME, ns = ...` at the top of
every file, and `ns` is the one table they all share. At load time files only
define functions and register themselves. Game data isn't trusted until
login.

| # | File | Why it sits here |
|---|---|---|
| 1–5 | `Libs\…` | Everything below uses `LibStub(...)`. LibStub first, CallbackHandler before AceComm (AceComm builds on it) |
| 6 | `Core\Init.lua` | Defines `ns:RegisterCore` / `ns:NewModule`, which every later file calls |
| 7 | `Locales\enUS.lua` | Later files capture `local L = ns.L` at load time |
| 8–16 | `Core\Events` → `DB` → `Log` → `Roster` → `PlayerEvents` → `Comm` → `Version` → `TestMode` → `Slash` | Registration order = initialization order. `DB` must initialize before `Log` reads the debug flag and before any module asks for storage |
| 16 | `Modules\Ticker\Ticker.lua` | Creates the module with `ns:NewModule("Ticker")` |
| 17–18 | `Stats.lua`, `Display.lua` | Attach to that module (`ns:GetModule("Ticker")`), so they must come after it |

Then the lifecycle:

```mermaid
sequenceDiagram
    participant G as WoW client
    participant I as Init (boot frame)
    participant C as Core services (in .toc order)
    participant M as Modules
    G->>G: run all .toc files (define + register only)
    G->>I: ADDON_LOADED "LooserPiml" (SavedVariables are loaded now)
    I->>C: OnInitialize: DB creates or migrates LooserPimlDB, Log hooks blocked-action events, Comm registers prefix LPiml, Slash registers /lp
    I->>M: OnInitialize: Ticker gets its storage, registers /lp stats
    G->>I: PLAYER_LOGIN (also after every /reload)
    I->>C: OnEnable: Events listens for ENCOUNTER_START/END, Roster scans group, Comm adds flush triggers, Version schedules HELLO
    I->>M: EnableModule for each module enabled in the DB: Ticker registers game events, its TICK handler and sims
    G->>M: PLAYER_ENTERING_WORLD (initial login: baseline only, nothing announced)
```

## One event end to end: my death on my friend's screen

Two clients, "Me" and my friend. Numbered steps are explained below the
diagram.

```mermaid
sequenceDiagram
    autonumber
    participant GA as WoW client (me)
    participant PE as PlayerEvents (me)
    participant TA as Ticker (me)
    participant SA as Stats (me)
    participant DA as Display (me)
    participant CA as Comm (me)
    participant LIB as AceComm + ChatThrottleLib (me)
    participant SRV as Game server
    participant CB as Comm (friend)
    participant TB as Ticker (friend)
    participant SB as Stats (friend)
    participant DF as Display (friend)

    GA->>PE: PLAYER_DEAD via Events dispatcher (SafeCall)
    PE->>TA: LP_PLAYER_DEAD after count-once check, WasDrowning(), zone name
    TA->>SA: Record(me, data)
    TA->>DA: ShowEvent(me, data)
    alt boss encounter active (Events:IsEncounterActive)
        DA->>DA: hold entry, 2 s watcher until the fight is over
    else
        DA->>GA: chat line + banner (Render)
    end
    TA->>CA: Send("TICK", data)
    opt IsRestricted(): encounter or InChatMessagingLockdown
        CA->>CA: Hold(entry), late = "encounter", start 5 s retry ticker
        Note over CA: Flush() on LP_ENCOUNTER_END, ADDON_RESTRICTION_STATE_CHANGED (Inactive), PLAYER_ENTERING_WORLD or the ticker
    end
    CA->>CA: Transmit(): Encode (AceSerializer, LibDeflate)
    alt test mode
        CA->>CA: Receive(text, me, "LOOPBACK"), dropped as own message
    else in a group
        CA->>LIB: SendCommMessage(LPiml, text, PARTY or RAID, onChunkSent)
        LIB->>SRV: C_ChatInfo.SendAddonMessage per chunk (max 255 bytes, throttled)
        opt client refuses a chunk
            LIB-->>CA: onChunkSent(didSend = false), OnSendFailed, Hold(atFront)
        end
        SRV-->>CA: CHAT_MSG_ADDON echo to me, ignored (own message)
        SRV->>CB: CHAT_MSG_ADDON chunks, AceComm reassembles, OnCommReceived
        CB->>CB: Receive(): Decode, own-echo, protocol and duplicate checks
        CB->>TB: OnTick(data, "Me-Realm", meta with late and test)
        TB->>TB: Sanitize (types, lengths, escape pipes)
        TB->>SB: Record(sender, event)
        TB->>DF: ShowEvent(sender, event, late)
        alt friend is in a boss fight
            DF->>DF: hold until LP_ENCOUNTER_END
        else
            DF->>DF: banner + chat line, "During the boss:" if late = "encounter"
        end
    end
```

1. The game fires `PLAYER_DEAD`. `Core/Events.lua` is the only frame
   registered for it and calls `PlayerEvents:PLAYER_DEAD` through
   `ns.SafeCall`, so one buggy handler can't break the others.
   PlayerEvents fires the internal `LP_PLAYER_DEAD` message, which the
   Ticker (and the Stats module) receive.
2. `PlayerEvents.dead` makes sure one death is counted once until
   `PLAYER_ALIVE`/`PLAYER_UNGHOST`. `WasDrowning()` looks at the breath
   mirror timer (see Restrictions).
3. Stats first, so the banner can say "Death #3".
4. **Local first**: my own banner never waits for the network. That works
   solo and during restrictions.
5. **Encounter hold, receiving side of the UI**: during a boss fight
   `Display` holds banners (my own too) and shows them afterwards. A 2 s
   watcher releases them even if no end event arrives.
6. `Comm:Send` is the single door to the network. Every module uses it.
7. **Encounter queue, sending side**: if `Comm:IsRestricted()` says no, the
   message goes into `Comm.queue` with `late = "encounter"` (or
   `"lockdown"`). Several triggers call `Flush()`, which re-checks and then
   uses the same `Transmit()`. `Transmit()` picks the channel only then, so
   a group that changed in the meantime is handled.
8. Encoding: AceSerializer (table → string), LibDeflate compress, then
   re-encode so the bytes are allowed on the addon channel.
9. **Test-mode loopback**: in test mode `Transmit()` never touches the
   network. It feeds the encoded text straight into our own `Receive()`,
   which drops it as "own message". The point is to prove that
   encode/decode works without anything leaving the client. Simulated
   *friends* use a separate entry point (next section).
10. AceComm splits into ≤255-byte chunks, ChatThrottleLib paces them, and
    the client API sends them.
11. **Refusals**: if the client still refuses (e.g. lockdown started
    between check and send), AceComm reports `didSend = false` per chunk.
    `Comm` puts the whole message back at the front of the queue, at most
    5 attempts.
12. The server echoes group messages to the sender. `Receive()` ignores
    its own name.
13. On the friend's side AceComm reassembles chunks and calls
    `Comm:OnCommReceived`.
14. `Receive()` decodes, then filters: own echo, other protocol version
    (except HELLO), and duplicates keyed by sender + session + id. Then it
    dispatches to every handler registered for `"TICK"`.
15. `Ticker:OnTick` → `Sanitize` copies only known fields with correct types
    and escapes `|`.
16. Stats count it; real events also go into the all-time stats.
17. Display: held if the friend is fighting, otherwise shown. The sender's
    `late` flag becomes the "During the boss:" prefix.

### Test mode: `/lp sim death Max`

```mermaid
sequenceDiagram
    participant U as /lp sim death Max
    participant TM as TestMode
    participant T as Ticker
    participant C as Comm
    participant S as Stats
    participant D as Display
    U->>TM: Sim("death", "Max"), refused unless test mode is on
    TM->>T: Simulate("death", "Max") (registered via RegisterSim)
    T->>C: SimulateReceive("Max", "TICK", data)
    C->>C: Encode, then Receive(text, "Max", "LOOPBACK", isTest = true)
    C->>T: OnTick(data, "Max-Realm", meta.test = true)
    T->>S: Record (session only, never all-time)
    T->>D: ShowEvent, banner tagged [test]
```

The fake friend's message runs the same decode → filter → handler →
stats → display path as a real one. Only the network is skipped. Without a
name (`/lp sim death`) it calls `OnOwnEvent` instead, the same path as a
real death of yours. `/lp sim boss` toggles `Events:SetSimulatedEncounter`,
which fires the same `LP_ENCOUNTER_START/END` messages as a real boss, so
both hold mechanisms run.

## Where the Forever/Midnight restrictions are handled

WoW: Forever uses Retail's (Midnight) addon rules. What that means here:

| Restriction | Where | How we deal with it |
|---|---|---|
| Addon messages blocked during boss encounters (and other chat-lockdown states: M+, PvP, possibly restricted maps) | `Comm:IsRestricted`, `Comm:Hold`/`Flush`, encounter state in `Events.lua` | Don't even try while restricted: queue, flush afterwards, mark as late. Signals: our ENCOUNTER_START/END tracking, `C_InstanceEncounter.IsEncounterInProgress()`, `C_ChatInfo.InChatMessagingLockdown()`, `ADDON_RESTRICTION_STATE_CHANGED` |
| The client may still refuse a send (result `AddOnMessageLockdown`) | `onChunkSent` → `Comm:OnSendFailed` | Requeue at the front, retry every 5 s, give up after 5 attempts. ChatThrottleLib alone would drop it |
| Secret values (API results we may not inspect) | `ns.IsSecret` (Init.lua), used in Roster, Events, Comm, Ticker | Check before any compare, arithmetic or concatenation; drop the value and degrade. Secret encounter state counts as "restricted"; secret breath timer means no "drowned" variant; secret unit identity means the member is skipped |
| `COMBAT_LOG_EVENT_UNFILTERED` can't be registered | `Ticker.lua` drowning section | No cause-of-death from the combat log. Drowning is derived from the breath mirror timer only |
| Events that don't exist on this client | `Events:Register` (`C_EventUtils.IsEventValid`) | Skipped with a debug line instead of a Lua error |
| Protected functions / blocked actions | `Log.lua` | We call none. ADDON_ACTION_BLOCKED/FORBIDDEN are recorded and shown in debug/test mode so a hit is obvious |
| Throttling (per prefix, server side) | ChatThrottleLib (via AceComm), `Version.HELLO_COOLDOWN`, queue cap | Messages only on real events; compressed to few chunks; HELLO bursts coalesced |
| No visible chat, no automation | By design; enforced by `spec/support/wow_mock.lua` | Output is `DEFAULT_CHAT_FRAME:AddMessage` + our own frame only |

Everything here that couldn't be verified offline is marked
`TODO(verify in-game)` in the code and listed in TESTING.md.

## How the tests see the addon

`spec/support/helpers.lua` reads `LooserPiml.toc`, expands the library XML
files and loads every file with `setfenv` into a fresh environment built by
`wow_mock.lua`. So each simulated client has its own globals, LibStub and
ChatThrottleLib, and two clients can run side by side in one Lua process.
Clients on a shared mock network exchange real AceComm chunks.
`ticker_spec.lua` → "two clients end to end" walks the whole diagram above.
