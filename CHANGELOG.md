## 0.15.0 (2026-07-18)

[Full Changelog](https://github.com/kottot13/spotme/compare/v0.14.1...v0.15.0) · [Previous Releases](https://github.com/kottot13/spotme/releases)

- **Route by coordinates**: type `/sm 41.8 66.6` to draw a trail to that spot — with the world map open the point lands on the viewed zone, otherwise on your current zone. Decimal commas (`41,8 66,6`) and comma-separated pairs (`41.8,66.6`) are accepted.
- **Coordinate field in the party panel**: a new input row at the bottom with **Go** and **Clear** buttons. It always shows the current target — however the route was started (typed coordinates, Shift+click on the map, or right-click on a group member).
- `/sm clear` clears the route from chat; `/way` works as a TomTom-style alias when TomTom isn't installed.
- Internal: navigation moved into its own module (`Nav.lua`) — no behavior changes.
