# SimDeck

<p align="center">
  <img src="../SimDeck/Resources/logo.png" alt="SimDeck Logo" width="96" height="96" />
</p>

<p align="center">
  <strong>Native macOS manager and multi-device streamer for Android emulators and iOS simulators.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%7C%20SwiftUI-orange" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
  <img src="https://img.shields.io/badge/MCP-Ready-purple" alt="MCP Ready" />
</p>

---

<p align="center">
  <img src="assets/simdeck-demo.gif" alt="SimDeck Live Demo" width="100%" />
</p>

- **[SimDeck/README.md](../SimDeck/README.md)** — features, architecture, build, MCP details
- **[SimDeck/AGENT.md](../SimDeck/AGENT.md)** — how agents drive devices through SimDeck
- **[PROJECT_STATE.md](PROJECT_STATE.md)** — verification status and architecture notes
- **[TASK.md](TASK.md)** — roadmap and remaining work
- **[SESSION_HANDOFF.md](SESSION_HANDOFF.md)** — where the last session stopped and what to run

## Download

[SimDeck 1.0.0](https://github.com/cuongdq88/simdeck/releases/tag/simdeck-v1.0.0)
(`SimDeck-1.0.0-macos-arm64.dmg`). Ad-hoc signed: after copying it to
Applications run `xattr -dr com.apple.quarantine /Applications/SimDeck.app`.

## Screenshots

| Multi-Device Streaming Dashboard |
|:---:|
| ![SimDeck Hero](assets/simdeck-hero.png) |

| Fast Device Creation | Android SDK Manager |
|:---:|:---:|
| ![Create Device](assets/simdeck-new-device.png) | ![SDK Manager](assets/simdeck-sdk-manager.png) |

## Requirements

macOS 14 or newer, Xcode with a simulator runtime, and an Android SDK with `platform-tools` and `emulator`. Creating AVDs needs no Java.

## Build

```bash
cd SimDeck
xcodegen generate
xcodebuild -project SimDeck.xcodeproj -scheme SimDeck \
  -configuration Release -derivedDataPath build-release build
open build-release/Build/Products/Release/SimDeck.app
```

## Agents

While the app runs it serves MCP on loopback at `http://127.0.0.1:8765/mcp`.
Agents must create and boot devices through it, never by running `emulator`
themselves: `start_device` boots headless and the screen appears inside
SimDeck.

- OpenCode in this repo uses the local bridge `SimDeck/bin/simdeck-mcp`, which
  starts SimDeck on demand.
- Shell-only agents: `SimDeck/bin/simdeck list|start|boot|tap|type|screenshot|stop`.

## Licence

MIT — see [LICENSE](../LICENSE). You may use, modify and redistribute SimDeck,
including commercially, as long as the copyright and permission notice stay
with it. © 2026 cuongdq88.

### Third-Party Notices

SimDeck was written as a fresh SwiftUI app, informed by:
- [SimUtil](https://github.com/dungngminh/simutil) (MIT)
- [emu](https://github.com/wasabeef/emu) (MIT)
- [serve-sim](https://github.com/EvanBacon/serve-sim) (Apache-2.0)

The notices and the full Apache text are in [third_party/](../third_party/); the bundled
`scrcpy-server` keeps its own licence file next to it. Apple and Google tools
are not redistributed: `adb`, `emulator`, `simctl` and Xcode's private
frameworks are used from the user's own installation.
