## 0.16.1 (2026-08-08)

[Full Changelog](https://github.com/kottot13/spotme/compare/v0.16.0...v0.16.1) · [Previous Releases](https://github.com/kottot13/spotme/releases)

- **Routes with several stops have been withdrawn.** They went out in 0.16.0 before they were finished. Routing is back to the 0.15.1 behaviour: one destination at a time, which works. The multi-stop version will return once it is ready.
- If you turned on *Route chain* in 0.16.0, the option is gone and your routes behave normally again.
- **New `/sm debug`.** Prints the addon version, client build, any recent errors and where the minimap button actually sits — paste it into a bug report instead of describing the symptom.
- **Errors are no longer silent.** A failure inside the addon could vanish without a trace, leaving something like the settings panel simply missing. Failures are now reported in chat and passed on to BugSack/BugGrabber.
