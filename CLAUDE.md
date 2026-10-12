# CLAUDE.md

LooserPiml is a WoW: Forever addon (Mainline/Midnight-style API, Interface
16001) for a fixed group of friends. Core services plus feature modules
(Ticker now; Inventory, Professions, Bets later).

- How it fits together: [ARCHITECTURE.md](ARCHITECTURE.md)
- Decisions, open questions, safety rules: [STATUS.md](STATUS.md)
- Test levels and the `TODO(verify in-game)` table: [TESTING.md](TESTING.md)

## Safety rules (non-negotiable)

Check every change against the rules in STATUS.md → "Safety rules": official
API only; never circumvent, derive or reconstruct secret values; no visible
chat (sync only through `ns.Comm`); no automation of game actions; all
traffic throttled. **If a feature conflicts with them, stop and ask instead of
working around it.** Never touch other addons, the WTF folder or game files.

**Communication only with the explicit, mutual LooserPiml friends list**
(hard rule, same weight as the ones above). Players without LooserPiml, or
who aren't on the player's list, must never receive anything from
LooserPiml, not even an invisible addon message:

- Send only through `ns.Comm:Send(type, data, { scope = ... })`; the scope
  (`handshake`, `friends`, `group`) and `Friends:Route` decide the
  recipients when the message really goes out. Never call
  `SendAddonMessage`/`SendCommMessage` yourself, never add a GUILD,
  Battle.net or broadcast path, never send anything to "discover" who runs
  LooserPiml.
- The group channel only if every other group member may receive the
  message; otherwise whispers to listed friends who are online.
- Incoming messages from senders who aren't listed are dropped
  (`Comm:Receive`); don't add handlers that bypass that.
- Leaderboard, "friends online" and sync include only listed friends who
  answered the handshake. Test mode and sample friends never send anything
  to real players.
- The test helpers check every send in every spec against the friends
  list. A new message type or code path needs a test that it keeps the
  rule.

## Code conventions

- **Comment every non-obvious WoW API behaviour or restriction workaround.
  Explain why, not what.** Examples of what needs a comment: event payload
  quirks (units, number vs boolean), event ordering assumptions, things that
  fire more or less often than you'd expect, secret-value handling, why a
  fallback exists, limits (255 bytes, 16-char prefix, throttles), anything
  that differs between Forever and Retail. A comment that only repeats the
  code is noise; leave it out.
- Behaviour that can't be verified offline gets `TODO(verify in-game)` in the
  code **and** a row in the TESTING.md table. Never guess silently.
- Secret values: call `ns.IsSecret(v)` before comparing, doing arithmetic,
  concatenating or indexing anything an API returned. If it is secret, drop
  the value and degrade the feature. Remember that `ns.IsSecret(x) or x` is
  safe (short-circuit), but `x == y` on a secret is not.
- Data from other clients is untrusted. Copy only known fields with checked
  types, cap string lengths and escape `|` (`"||"`) before anything reaches a
  FontString or the chat frame.
- Output is local only: `ns.Log:Print` / `DEFAULT_CHAT_FRAME:AddMessage` and
  our own frames. Never `SendChatMessage`; the test mock errors on it.
- User-visible strings go into `Locales/enUS.lua` (`ns.L`).
- New features are modules (`ns:NewModule`). Register events and message
  handlers with the module itself as owner so disabling cleans up. Store data
  via `ns.DB:GetModuleDB`. A saved-layout change needs a migration in
  `Core/DB.lua` plus a `SCHEMA_VERSION` bump.
- WoW Lua is 5.1: no `goto`, `//`, bitwise operators, `io`, `os`, `require`.
  Everything is `local`; the only intended globals are listed in the hygiene
  test in `spec/core_spec.lua`.
- Style: tabs, file header comment stating the file's job, match the
  surrounding code.

## Tests

- Run the suite after every change. It must be green before you commit:
  `powershell -ExecutionPolicy Bypass -File tools\run-tests.ps1`
- New behaviour gets a spec. When the mock (`spec/support/wow_mock.lua`)
  needs a new API, mirror the real semantics from warcraft.wiki.gg, including
  return codes and secret behaviour.
- When writing Lua files from PowerShell, write UTF-8 **without BOM**. Lua 5.1
  can't parse a BOM. Prefer the editor tools.

## Git

- Small commits, one logical change each, with descriptive messages: an
  imperative subject of 72 characters or less, and a body that explains why
  when it isn't obvious.
- Tests green before each commit. `Libs/` is never committed (fetched).

## Docs

- **Keep ARCHITECTURE.md up to date whenever structure changes**: new or
  renamed files, `.toc` load order, the message flow or diagram, the
  restriction handling.
- STATUS.md: decisions with reasons, open questions, next steps.
- CHANGELOG.md: user-visible changes under "Unreleased".
- TESTING.md: new in-game checks and `TODO(verify in-game)` rows.

## Environment

Windows, PowerShell. Test toolchain: `%LOCALAPPDATA%\LooserPiml\lua51`
(`tools/setup-test-env.ps1`). Dev client: the Forever beta folder `<WoW>\_classic_beta_`,
linked by junction (`tools/link-addon.ps1`).
