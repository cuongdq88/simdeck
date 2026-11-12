# SimDeck

<p align="center">
  <img src="SimDeck/Resources/logo.png" alt="SimDeck Logo" width="96" height="96" />
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
  <img src="docs/assets/simdeck-demo.gif" alt="SimDeck Live Demo" width="100%" />
</p>
<p align="center"><em>Live multi-device streaming and fluid touch interaction across Android 16 and iOS simulators in SimDeck.</em></p>

SimDeck is a native macOS application built with SwiftUI to create, boot, stream, interact with, and delete Android emulators and iOS simulators simultaneously in a single sleek window — all without needing Android Studio.

---

## ⬇️ Download

[**SimDeck 1.0.0**](https://github.com/cuongdq88/simdeck/releases/tag/simdeck-v1.0.0) — `SimDeck-1.0.0-macos-arm64.dmg` (macOS 14+, Apple silicon). The build is ad-hoc signed, so clear the quarantine flag once after copying it to Applications:

```bash
xattr -dr com.apple.quarantine /Applications/SimDeck.app
```

It still needs Xcode (for `simctl` and the simulator runtimes it links against) and the Android SDK (`adb`, `emulator`) on the Mac.

---

## ✨ Features

- **Multi-Device Unified Streaming**: Stream multiple Android emulators and iOS simulators concurrently in responsive adaptive grid or spotlight layouts.
- **Hardware-Accelerated Decoding**: High-frame-rate Android streaming via a custom embedded `scrcpy-server` protocol client paired with Apple's `VideoToolbox` H.264 hardware decoding.
- **Native iOS Simulator Integration**: Zero-copy framebuffer streaming using private `SimulatorKit` / `CoreSimulator` callbacks with low-latency touch and keyboard input.
- **Realistic Device Frames**: Native Xcode DeviceKit bezels, dynamic island/notch cutouts, and clickable hardware buttons.
- **No Heavy IDE Dependencies**: Create and edit Android Virtual Devices (AVDs) directly through `config.ini` templates — no Java runtime or `avdmanager` required.
- **Built-in Android SDK Manager**: Discover, inspect, and install Android SDK system images directly within the app.
- **AI Agent & MCP Ready**: Serves a loopback Model Context Protocol (MCP) HTTP endpoint (`http://127.0.0.1:8765/mcp`) with 25 tools for automated headless device control — including `run_scenario`, which plays the same steps on several devices at once — plus the `SimDeck/bin/simdeck` CLI and a stdio bridge (`SimDeck/bin/simdeck-mcp`) for agents that cannot speak HTTP.
- **Whole-Grid Recording**: Records the whole SimDeck window with ScreenCaptureKit to an H.264 MP4 at four quality levels (15/24/30/60 fps, 720p, 1280 px or full size), with a recordings browser that opens, reveals or trashes the files.
- **Notifications & Settings**: In-app notification panel with a 50-item history, and a Settings sheet (⌘,) for the default headless mode, recording folder, layout, device frame and grid-recording quality.
- **Developer Tools**: Live Logcat viewer with severity filters, ADB Wi-Fi pairing (mDNS / manual code), and one-click screenshots/screen recordings saved to disk.

---

## 📸 Screenshots

| Multi-Device Streaming Dashboard |
|:---:|
| ![SimDeck Hero](docs/assets/simdeck-hero.png) |

<br/>

| Fast Device Creation | Android SDK Manager |
|:---:|:---:|
| ![Create Device](docs/assets/simdeck-new-device.png) | ![SDK Manager](docs/assets/simdeck-sdk-manager.png) |

---

## 📋 Requirements

- **macOS 14 (Sonoma)** or newer.
- **Xcode** with at least one installed iOS Simulator runtime.
- **Android SDK** with `platform-tools` (`adb`) and `emulator` installed (`ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `~/Library/Android/sdk`).
- *Note:* Java and Android Studio are **not** required.

---

## 🚀 Build & Run

### 1. Generate Xcode Project
SimDeck uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to maintain clean, declarative project settings:

```bash
cd SimDeck
xcodegen generate
```

### 2. Build Release App

```bash
xcodebuild -project SimDeck.xcodeproj -scheme SimDeck \
  -configuration Release -derivedDataPath build-release build

# Launch the app
open build-release/Build/Products/Release/SimDeck.app
```

> **Note:** SimDeck signs with the `com.apple.security.cs.disable-library-validation` entitlement (`Config/SimDeck.entitlements`) to load Xcode's private `CoreSimulator` and `SimulatorKit` frameworks at runtime for iOS frame capture and input.

---

## 🤖 AI Agents & MCP Server

SimDeck acts as an automated device test harness for AI coding agents (such as Claude, OpenCode, Codex, and custom bots). When running, SimDeck serves an MCP server on `http://127.0.0.1:8765/mcp`.

Add SimDeck to your agent configuration:

```json
{
  "mcp": {
    "simdeck": {
      "type": "remote",
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

### Supported MCP Tools (25)

- `list_devices`, `get_device_catalogs` — devices, images and hardware profiles.
- `create_avd`, `create_simulator`, `delete_device` — provision and remove devices.
- `start_device`, `stream_device`, `stop_device`, `shutdown_device` — boot headless, open a tile, shut down.
- `connect_device`, `pair_device`, `disconnect_device` — ADB over Wi-Fi.
- `tap` (normalized point or accessibility label), `swipe`, `type_text`, `press_button`, `find_elements` — input and lookup. `find_elements` and `tap {label}` read the Android accessibility tree and return an explicit error on iOS simulators.
- `install_app`, `launch_app` — install an APK or simulator `.app`, then launch it.
- `screenshot`, `record_device`, `record_grid` — capture a frame, one device or the whole grid.
- `get_spotlight` — current layout, focus and open streams.
- `run_scenario`, `stop_scenario` — run the same steps on several devices (Android and iOS) at once — each device reports `ok`, the step it failed at and per-step ms — and stop a run. Steps: `tap` (point or label), `swipe` (with `until`), `press`, `wait`, `launch` (per-platform ids), `type`, `assert_visible`, `assert_not_visible`, plus `repeat` and `if_visible` / `if_not_visible`.

For shell-only workflows, use the bundled CLI bridge:

```bash
SimDeck/bin/simdeck list
SimDeck/bin/simdeck start android:E1
SimDeck/bin/simdeck swipe ios:EF4916C0-D051-406B-BA3A-B2AA50CA96D1 0.2 0.5 0.8 0.5
SimDeck/bin/simdeck screenshot android:E1
SimDeck/bin/simdeck call run_scenario '{"devices":["android:E1"],"steps":[{"action":"wait","ms":500}]}'
SimDeck/bin/simdeck call stop_scenario '{}'
```

`call <tool> [json]` reaches any MCP tool. Clients that can only launch local stdio servers use `SimDeck/bin/simdeck-mcp`, which starts SimDeck on demand and forwards JSON-RPC to the same endpoint.

---

## 📁 Repository Structure

```
simdeck/
├── SimDeck/              # SwiftUI native application
│   ├── Sources/          # App, UI, Streaming, MCP, Android, Apple
│   ├── Resources/        # Assets, logos, bundled scrcpy-server
│   ├── bin/              # Agent CLI bridge (`simdeck`, `simdeck-mcp`)
│   └── project.yml       # Declarative XcodeGen configuration
├── docs/                 # Documentation & media assets
│   ├── assets/           # Screenshots, demo video, and GIF
│   ├── PROJECT_STATE.md  # Engineering state and verification log
│   ├── SESSION_HANDOFF.md # Where the last session stopped
│   └── TASK.md           # Roadmap and ongoing tasks
├── third_party/          # Third-party notices and licenses
└── LICENSE               # MIT License
```

---

## 📄 License & Third-Party Notices

MIT — see [LICENSE](LICENSE). You may use, modify and redistribute SimDeck, including commercially, as long as the copyright and permission notice stay with it. © 2026 cuongdq88.

### Third-Party Notices

SimDeck was written as a fresh SwiftUI app, informed by:
- [SimUtil](https://github.com/dungngminh/simutil) (MIT)
- [emu](https://github.com/wasabeef/emu) (MIT)
- [serve-sim](https://github.com/EvanBacon/serve-sim) (Apache-2.0)

The notices and the full Apache text are in [third_party/](third_party/); the bundled `scrcpy-server` keeps its own licence file next to it ([SimDeck/Resources/](SimDeck/Resources/)). Apple and Google tools are not redistributed: `adb`, `emulator`, `simctl` and Xcode's private frameworks are used from the user's own installation.
