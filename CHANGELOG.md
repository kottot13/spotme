## 0.15.1 (2026-08-02)

[Full Changelog](https://github.com/kottot13/spotme/compare/v0.15.0...v0.15.1) · [Previous Releases](https://github.com/kottot13/spotme/releases)

- **Routes no longer appear on their own.** Dragging the world map with `Shift` held used to drop a waypoint, because the game reports a finished drag the same way it reports a click. `Shift`+click still sets a route; panning the map no longer does.
- **The trail stays on the map.** A target that belongs to another zone used to trail dots off the map toward nothing; the path is now kept within the map it is drawn on.
- **Routes clean up after themselves** — cleared when you arrive (distance adjustable in the options, or switch it off) and when you travel to another continent.
- **The minimap button is back**, along with the minimap glow and the minimap trail. They no longer break when another addon moves or restyles the minimap.
- The `/way` command has been removed. Use `/sm 41.8 66.6`, the coordinate field in the party panel, or `Shift`+click on the map.
