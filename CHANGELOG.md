## 0.14.1 (2026-07-08)

[Full Changelog](https://github.com/kottot13/spotme/compare/v0.14.0...v0.14.1) · [Previous Releases](https://github.com/kottot13/spotme/releases)

- **Fixed a taint bug** that could block protected actions (Hearthstone, action-bar buttons) and prompt you to disable SpotMe. An options dropdown was registered with a function in place of its default value, which tainted the Settings panel's secure code.
- Map navigation now opens the world map through a taint-safe path, so showing a party member or a route can no longer block protected actions.
- Added a **Minimap button** toggle to the in-game options panel — show or hide the SpotMe minimap button without a slash command.
