# SimDeck

A native macOS app for creating, running, streaming and deleting Android
emulators and iOS simulators, without Android Studio. Built with SwiftUI; the
Flutter project and the `simutil_*` packages it started from have been removed.

- **[SimDeck/README.md](SimDeck/README.md)** — features, architecture, build, MCP
- **[SimDeck/AGENT.md](SimDeck/AGENT.md)** — how agents drive devices through SimDeck
- **[TASK.md](TASK.md)** — remaining work

## Requirements

macOS 14 or newer, Xcode 27 with a simulator runtime, and an Android SDK with
`platform-tools` and `emulator`. Creating AVDs needs no Java.

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

## Layout

| Path | Contents |
| --- | --- |
| `SimDeck/` | the app: SwiftUI sources, agent bridge, MCP server, resources |
| `third_party/` | upstream MIT licence texts |
| `LICENSE` | SimUtil's MIT licence, unchanged |
