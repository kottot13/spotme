# Changelog

All notable changes to SpotMe are listed here. Newest first.

## v0.13.0

- **Navigation.** Right-click a party/raid member — or `Shift`+left-click any spot on the
  world map — to draw a movable on-screen arrow plus a class-colored dotted trail on both the
  world map and the minimap.
- **Clear route** button on the open world map, in addition to right-clicking the arrow, so a
  route can be dropped without leaving the map.
- **Navigation color** (`/sm navcolor`): the target's class color, or a fixed palette (red,
  cyan, green, yellow, black, white). A map point is routed in the placer's (your) class color.
- **Party panel** additions: a class filter (icon row), sort order (roster / nearest / farthest /
  by class), and a button that opens the options panel.
- **Minimap glow fix.** The glow now renders on the reworked 12.0 minimap (raised the frame
  strata and level so it is no longer hidden under the map layers). `/sm status` now also reports
  the minimap marker state.

## v0.12.0

- **Party locator.** A minimap button opens a scrollable party/raid panel with class-colored
  names, live coordinates and a copy button. Click a member to open the map on their location
  with a class-colored glow highlight.

## v0.11.0

- Initial public release: an animated glow marking your position on the world map and the
  minimap, 6 themes, color presets / rainbow / class color / custom RGB, an in-game options
  panel and full slash commands.
