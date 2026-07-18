<!-- Project-page description for CurseForge / Wago. Paste into the Description field.
     Summary (one line): Find yourself and your group — an animated glow marks your
     position, and a party panel locates and navigates to everyone in your party or raid. -->

# SpotMe

**Find yourself and your group — an animated glow marks your position, and a party panel locates and navigates to everyone in your party or raid.**

Ever opened your map in a busy zone and wasted a few seconds hunting for your own arrow among dozens of icons? SpotMe fixes that first: it wraps your position in a smooth, animated glow — a breathing core and expanding rings — so your location jumps out the moment the map opens. It doesn't replace or hide your arrow; the game keeps drawing and rotating it exactly as before.

Then it does the same for your group. A minimap button opens a party or raid panel with class-colored names, live coordinates and a copy button. Right-click a member — or Shift+left-click any spot on the map — and SpotMe lays a class-colored trail plus an on-screen arrow that guide you straight there.

## Features

- **Glow on the world map (M) and the minimap** — each can be turned on or off independently.
- **6 built-in themes** — Arcane, Fire, Lightning, Ice, Holy and Shadow — each with its own texture, color and animation feel.
- **Any color you like** — 12 presets, a smooth rainbow cycle, your class color, or a custom RGB value.
- **Smooth, subtle animation** — a breathing core, phase-shifted expanding rings and a soft flicker. Nothing flashy or distracting.
- **In-game options panel** (native WoW Settings UI) plus full slash commands.
- **Party locator** — a minimap button opens a scrollable list of your party or raid: class-colored names, live coordinates, a copy button, a class filter and sorting (roster / nearest / farthest / by class). Click a member to show them on the map with a class-colored glow.
- **Navigation** — right-click a member, or Shift+left-click any spot on the world map, to get a movable on-screen arrow and a dotted trail on both the world map and the minimap. Clear the route from the arrow or a Clear route button on the map.
- **Route by coordinates** — type `/sm 41.8 66.6` in chat, or use the coordinate field at the bottom of the party panel (Go / Clear buttons). The field always shows the current target, however the route was started. `/way` works as an alias when TomTom isn't installed.
- **Fully customizable trail** — pick the marker style (dots, dashes, arrows or a solid line), an optional flowing animation with adjustable speed, plus size, color (class or a fixed palette including pink), black outline and spacing — all set separately for the world map and the minimap.
- **Localized** — displayed in your client's language (English and Russian, with more easy to add).
- **Lightweight** — no external libraries, no measurable performance cost.

## Slash commands

Open the options panel with **/sm** (or Esc → Options → AddOns → SpotMe). The full list:

| Command | Description |
| --- | --- |
| `/sm` | Open the configuration panel |
| `/sm help` | List every command in chat |
| `/sm world` | Toggle the glow on the world map |
| `/sm minimap` | Toggle the glow on the minimap |
| `/sm on` · `/sm off` | Turn the glow on / off everywhere |
| `/sm theme fire` | Switch theme: arcane, fire, lightning, ice, holy, shadow |
| `/sm class` | Use your class color |
| `/sm rainbow` | Smooth rainbow color cycle |
| `/sm gold` | Color preset: neon, ice, fire, toxic, gold, white, crimson, azure, emerald, violet, sunset, aqua |
| `/sm color 1.0 0.3 0.95` | Custom RGB color (values 0–1) |
| `/sm speed 0.1` | Rainbow cycle speed |
| `/sm arrow 40` | Native arrow size on the world map (default 27) |
| `/sm glowsize 85` | Glow size on the world map |
| `/sm minisize 46` | Glow size on the minimap |
| `/sm flicker` | Toggle the soft brightness flicker |
| `/sm party` | Open the party / raid locator panel |
| `/sm button` | Show or hide the minimap button |
| `/sm 41.8 66.6` | Route to coordinates (open map's zone, else your zone); `41,8 66,6` and `41.8,66.6` work too |
| `/sm clear` | Clear the current route |
| `/way 41.8 66.6` | TomTom-style alias (only when `/way` is free) |
| `/sm navcolor class` | Arrow color: class, red, cyan, green, yellow, black, white, pink |
| `/sm dotcolor class` | Trail color (same palette) |
| `/sm status` | Print the current state in chat |
| `/sm reset` | Reset all settings and reload |

Slash command: **/sm**.

![Party panel with the coordinate field](https://raw.githubusercontent.com/kottot13/spotme/main/media/ui.png)

## Mouse

- In the party panel: **left-click** a member to show them on the map, **right-click** to navigate to them.
- The coordinate field at the bottom of the panel: type coordinates and press **Go** (or Enter) to route there; **Clear** drops the route. The field mirrors the current target.
- **Shift + left-click** anywhere on the world map to route to that exact spot.
- Clear a route with a **right-click on the arrow**, the **Clear route** button on the open map, the panel's **Clear** button, or `/sm clear`.

## Feedback

Found a bug or have an idea? Open an issue on the source repository — contributions and translations are welcome.
