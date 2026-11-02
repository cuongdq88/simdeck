# Third-party notices

SimDeck itself is MIT-licensed (see [../LICENSE](../LICENSE)). It was written
as a fresh SwiftUI app, informed by these projects; their notices are kept
here and must stay with any redistribution.

| Project | Licence | What it informed |
| --- | --- | --- |
| [SimUtil](https://github.com/dungngminh/simutil) | MIT, © 2026 dungngminh | Design system, sidebar/tile behaviour, MCP tooling | 
| [emu](https://github.com/wasabeef/emu) | MIT, © 2025 Daichi Furiya | AVD / system image / iOS simulator behaviour |
| [serve-sim](https://github.com/EvanBacon/serve-sim) | Apache-2.0, © Evan Bacon | Simulator framebuffer capture and HID input; `SimFrameworks`, `SimulatorCapture` and `SimulatorHID` are derived from it |
| [scrcpy](https://github.com/Genymobile/scrcpy) | Apache-2.0 | The `scrcpy-server` bundled in `SimDeck/Resources`, with its licence file next to it |

- `SIMUTIL-LICENSE` — SimUtil's MIT text, unchanged.
- `EMU-LICENSE` — emu's MIT text, unchanged.
- `APACHE-2.0.txt` — the Apache License 2.0, for serve-sim and scrcpy.
- `SERVE-SIM-NOTICE` — serve-sim's copyright and origin.

SimDeck does not redistribute Apple or Google code. `adb`, `emulator`,
`xcrun simctl` and Xcode's private CoreSimulator/SimulatorKit frameworks are
used at runtime from the user's own installation.
