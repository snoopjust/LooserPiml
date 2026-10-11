# LooserPiml

A small World of Warcraft: Forever addon for a fixed group of friends. It shows
what happens to your friends: who levelled up, who died (again), who drowned,
and who walked into a dungeon. You also get a ranking to settle who the
Death King is.

> Working title. Free, open source, no ads, no donation requests.

**Status:** MVP (Core + Ticker). Group Inventory, Profession Directory and
Group Bets are planned. See [STATUS.md](STATUS.md).

## Fair play

LooserPiml only uses the official in-game Lua API. It never automates game
actions and never writes into visible chat. Friends' clients talk to each
other through hidden addon messages, which are throttled and paused while
the game restricts them (boss encounters). If a value is protected
("secret") the feature is skipped instead of worked around. Details are in
[STATUS.md](STATUS.md#safety-rules).

## For friends: install

### WowUp (recommended, updates automatically)

1. Install [WowUp](https://wowup.io). WoW: Forever support started in the
   v2.24.0 betas, so use that version or newer.
2. In WowUp, select your **WoW: Forever** client.
3. **Get Addons** → **Install from URL** → paste
   `https://github.com/snoopjust/LooserPiml` → **Install**.
4. That's it. WowUp picks up new releases by itself.

### Manual (fallback)

1. Download the latest `LooserPiml-vX.Y.Z.zip` from
   [Releases](https://github.com/snoopjust/LooserPiml/releases).
2. Extract it into your Forever client's AddOns folder so that this file
   exists: `World of Warcraft\_classic_beta_\Interface\AddOns\LooserPiml\LooserPiml.toc`
   (beta folder; the folder name at launch may differ).
3. Restart the game. To update, repeat with the new zip.

If the addon list shows LooserPiml as "out of date" after a game patch,
tick "Load out of date AddOns" until a new release is out.

## Usage

Nothing to configure: events show up as a banner in the middle of the screen
and as a line in your chat window (only you see it).

| Command | What it does |
|---|---|
| `/lp` | Help |
| `/lp stats` | Death King and rankings (this session and all-time) |
| `/lp version` | Your version and the versions in your group |
| `/lp test on\|off` | Test mode: nothing is sent, fake group members appear |
| `/lp sim <event> [name]` | In test mode: `death`, `drown`, `levelup`, `enter`, `leave`, `boss` |
| `/lp selftest` | Checks libraries, encoding and the real message transport |
| `/lp debug on\|off` | Debug log, including blocked actions and Lua errors |
| `/lp log [count]` | Prints the recent debug log |

## Development (Windows)

How the pieces fit together (file purposes, load order, an event traced end
to end, restriction handling): [ARCHITECTURE.md](ARCHITECTURE.md).
Conventions for working on the code: [CLAUDE.md](CLAUDE.md).

The repository root is the addon folder.

```
LooserPiml.toc
Core/       Init (modules, lifecycle), Events, DB, Log, Roster, Comm, Version, TestMode, Slash
Locales/    enUS.lua (all user-visible strings)
Modules/Ticker/   Ticker (detect + broadcast + receive), Display (banner), Stats
Libs/       fetched, not committed (tools/fetch-libs.ps1 or .pkgmeta externals)
spec/       busted tests + WoW API mock
tools/      link-addon.ps1, fetch-libs.ps1, setup-test-env.ps1, run-tests.ps1
```

### One-time setup

```bash
powershell -ExecutionPolicy Bypass -File tools\fetch-libs.ps1
```

```bash
powershell -ExecutionPolicy Bypass -File tools\link-addon.ps1
```

`link-addon.ps1` creates a directory junction
`<client>\Interface\AddOns\LooserPiml` → this repo (default client:
`C:\Program Files (x86)\World of Warcraft\_classic_beta_`, the standard install
location; override with `-WowClient`). It never
deletes anything and `-Remove` only removes the junction. Don't install
LooserPiml through WowUp on the same client while the junction exists.

### Tests

The offline suite runs the real addon files and libraries under Lua 5.1 with
a WoW API mock, including two clients talking to each other.

Setup, once. This installs MinGW GCC and hererocks, then builds Lua 5.1, LuaRocks and busted into
`%LOCALAPPDATA%\LooserPiml\lua51`:

```bash
winget install --id BrechtSanders.WinLibs.POSIX.UCRT --exact
```

```bash
python -m pip install --user hererocks
```

```bash
powershell -ExecutionPolicy Bypass -File tools\setup-test-env.ps1
```

Run (extra arguments go to busted, e.g. `--filter=Comm`):

```bash
powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1
```

In-game and two-player checks: [TESTING.md](TESTING.md).

### Releasing

1. Update `CHANGELOG.md`.
2. Tag and push: `git tag v0.1.0` then `git push origin v0.1.0`.
3. The GitHub Action runs the tests and builds `LooserPiml-v0.1.0.zip` with
   [BigWigsMods/packager](https://github.com/BigWigsMods/packager). The
   libraries are embedded and `@project-version@` becomes `v0.1.0`. The zip
   is attached to a GitHub release, and WowUp sees it.

The repo must be public so WowUp can read releases without a token.

### Writing a new module

```lua
local _, ns = ...
local Bets = ns:NewModule("Bets")

function Bets:OnInitialize()
	self.db = ns.DB:GetModuleDB(self.name, { open = {} }) -- SavedVariables
	ns.Slash:Register("bet", function(args) ... end, "<text>", "start a bet")
end

function Bets:OnEnable()
	ns.Events:Register(self, "PLAYER_DEAD")                 -- game events
	ns.Comm:RegisterHandler(self, "BET", self.OnBetMessage)  -- hidden group messages
	ns.TestMode:RegisterSim(self, { "bet" }, self.Simulate)  -- /lp sim bet Max
end

function Bets:OnBetMessage(data, sender, meta) ... end
-- send with ns.Comm:Send("BET", { ... })
```

Disabling a module unregisters its events and message handlers. If the saved
data layout changes, add a migration in `Core/DB.lua`.

## License

MIT, see [LICENSE](LICENSE). Embedded libraries keep their own licenses
(Ace3: BSD-style, LibDeflate: zlib).
