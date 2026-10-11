# Changelog

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
