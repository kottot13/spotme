<div align="center">

# SpotMe

**Highlights your position with a customizable animated glow on the world map and minimap, so you can spot yourself at a glance.**

![SpotMe on the world map](media/spotme.png)

</div>

---

Busy map full of icons and you can't find your own arrow? SpotMe wraps your player
position in a smooth animated glow — a breathing core plus expanding rings — so your
location pops out instantly. It doesn't replace the native arrow (the game keeps rotating
it correctly); it just makes it easy to spot.

## Features

- 🔦 **Glow around your position** on the world map (`M`) and on the minimap — each toggled independently.
- 🎨 **6 themes** — Arcane, Fire, Lightning, Ice, Holy, Shadow — each with its own textures, color and animation.
- 🌈 **Any color** — 12 presets, a rainbow mode, your class color, or a custom RGB value.
- ✨ **Smooth animation** — breathing core, phase-shifted expanding rings, soft flicker.
- ⚙️ **In-game options panel** (native Settings UI) and full slash commands.
- 👥 **Party locator** — a minimap button opens a scrollable panel of your party or raid with class-colored names, live coordinates and a copy button; click a member to open the map on their location with a class-colored glow.
- 🌍 **Localized** — shows in your client's language (English / Russian, more easy to add).
- 🪶 Lightweight, no external libraries.

## Installation

1. Copy the `SpotMe` folder into:
   - **Windows:** `World of Warcraft\_retail_\Interface\AddOns\`
   - **macOS:** `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
2. Fully restart the client (a freshly added folder is only detected on launch), then
   enable **SpotMe** in the AddOns list. Code updates apply with `/reload`.

## Configuration

Open the panel with **`/sm`** (or `Esc → Options → AddOns → SpotMe`), or use slash commands.

**Where to show**
| Command | Action |
| --- | --- |
| `/sm world` | toggle glow on the world map |
| `/sm minimap` | toggle glow on the minimap |
| `/sm on` / `/sm off` | toggle everywhere |

**Themes**
```
/sm theme arcane | fire | lightning | ice | holy | shadow
```

**Color**
```
/sm neon ice fire toxic gold white crimson azure emerald violet sunset aqua
/sm rainbow           smooth color cycle
/sm class             your class color
/sm color 1.0 0.3 0.95   custom RGB (0–1)
/sm speed 0.1         rainbow speed
```

**Sizes & misc**
| Command | Action |
| --- | --- |
| `/sm arrow 40` | native arrow size on the world map (default 27) |
| `/sm glowsize 85` | glow size on the world map |
| `/sm minisize 46` | glow size on the minimap |
| `/sm flicker` | toggle the soft brightness flicker |
| `/sm status` | show current state |
| `/sm reset` | reset all settings |

**Party locator**
| Command | Action |
| --- | --- |
| `/sm party` | open the party/raid locator panel |
| `/sm button` | show/hide the minimap button |

Aliases: `/spotme`, `/sm`, `/fa`.

## How it works

- The native player arrow is drawn by the engine (`GroupMembersPin`); its position comes
  from `C_Map.GetPlayerMapPosition`. Our glow is a separate frame on the map canvas at the
  same point, kept at a constant on-screen size while zooming.
- On the world map the native arrow is slightly enlarged via a hook on
  `GroupMembersPinMixin:SynchronizePinSizes`.
- Ping textures are yellow, so they are desaturated before tinting — that keeps every color accurate.

## License

MIT — see [LICENSE](LICENSE).
