## 0.16.2 (2026-08-08)

[Full Changelog](https://github.com/kottot13/spotme/compare/v0.16.1...v0.16.2) · [Previous Releases](https://github.com/kottot13/spotme/releases)

- **Fixed the error 0.16.1 could throw on login** — `PartyPanel.lua:549: attempt to index a nil value`. The minimap button was set up straight from its own login handler while the settings were still being loaded elsewhere; whichever ran first was down to luck, and losing meant the button was never placed. Setup now waits until the settings are actually there.
- If 0.16.1 left you without a minimap button, it comes back on its own — nothing to reset.
