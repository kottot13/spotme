## 0.16.0 (2026-08-08)

[Full Changelog](https://github.com/kottot13/spotme/compare/v0.15.1...v0.16.0) · [Previous Releases](https://github.com/kottot13/spotme/releases)

- **Routes with several stops.** Switch on *Route chain* in the options, then `Ctrl`+`Shift`+click the map to add up to 10 stops. The map draws the whole route with numbered points, while the arrow and the minimap lead to the nearest one.
- Reaching a stop moves you on to the next one automatically; `Ctrl`+`Shift`+click a stop again to remove it.
- A route now survives a reload and announces itself in chat when it comes back, so it never reappears silently.
- **New `/sm debug`.** Prints the addon version, client build, any recent errors and where the minimap button actually sits — paste it into a bug report instead of describing the symptom.
- **Errors are no longer silent.** A failure inside the addon used to vanish without a trace — that is how the minimap button could end up missing after login with nothing in chat to explain it. Failures are now reported, and passed on to BugSack/BugGrabber.
- **Fixed:** the game's own white dotted trail kept hanging on the map after a route was cleared. Clearing now removes the game's pin as well, and a new option lets you skip that pin entirely.
