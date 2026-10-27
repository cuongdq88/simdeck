<p align="center">
  <img src="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png" alt="SimDeck desktop" width="128" />
</p>

# SimDeck desktop

Flutter desktop app: a window that creates, streams and controls many Android
emulators/devices and iOS simulators side by side. This package is part of
[SimDeck](../README.md); the macOS app is what the cask installs.

- Start devices headless (no emulator window / Simulator app) and stream
  them into the grid; stop them; slim iOS simulators to save memory.
- Touch, swipe and navigation buttons on every stream; Apple device frames
  for simulators (from your Xcode), drawn frames otherwise.
- Grid or spotlight layouts (one stream large, the rest in a strip).
- Record one device or the whole grid to `~/Movies/SimDeck`.
- Right-click a device for per-device settings (headless, cold boot,
  stream resolution / frame rate / bit rate).
- Clear Xcode DerivedData (macOS) from the top bar or the tray menu, after a
  confirmation.
- MCP server for agents, see below.

## MCP server

SimDeck serves [MCP](https://modelcontextprotocol.io) over HTTP at
`http://127.0.0.1:8765/mcp` (loopback only; set `SIMDECK_MCP_PORT` to change
the port). Click the plug icon in the top-right corner for a copy-ready setup
for OpenCode, Claude Code, Codex, Cursor, Gemini CLI and VS Code; the tray
menu copies the URL. For OpenCode, add to `opencode.json`:

```json
{
  "mcp": {
    "simdeck": { "type": "remote", "url": "http://127.0.0.1:8765/mcp", "enabled": true }
  }
}
```

For example for Claude Code:

```bash
claude mcp add --transport http simdeck http://127.0.0.1:8765/mcp
```

| Tool | What it does |
| ---- | ------------ |
| `list_devices` | Devices with state, slim mode, streaming (with `fps` shown), and `recording_seconds` while recording |
| `get_device_catalogs` | Installed Android APIs with their tag/ABI pairs, hardware profiles, iOS device types and runtimes |
| `create_avd` / `create_simulator` | Create a device from those catalogs (then `start_device` boots it headless) |
| `delete_device` | Delete a shut-down device; the shared-dir / running / physical guards apply |
| `get_spotlight` | Stream layout, the device shown large, how long it and the grid have been recording |
| `start_device` / `shutdown_device` | Boot (headless by default) or shut down an emulator / simulator |
| `stream_device` | Show a running device in the grid |
| `tap` / `swipe` / `press_button` | Input with coordinates normalized to 0..1; back (Android), home, recents, lock |
| `run_scenario` | The same steps (`tap`, `swipe`, `press`, `wait`) on several Android and iOS devices in parallel, all starting together; reports each device's outcome and timing |
| `screenshot` | PNG of a running device |
| `record_device` / `record_grid` | Start / stop a recording; returns the file when stopping |
| `set_slim` | iOS simulator: turn background services off / on (reboots a running one) |

A scenario on every streamed device:

```json
{
  "steps": [
    { "action": "press", "button": "home" },
    { "action": "swipe", "x1": 0.8, "y1": 0.5, "x2": 0.2, "y2": 0.5 },
    { "action": "wait", "ms": 800 },
    { "action": "tap", "x": 0.5, "y": 0.4 }
  ]
}
```

Pass `devices` (ids or names) to pick devices; every step is checked before
any device moves. iOS simulators that are not slim yet are switched to Slim
first (rebooted in parallel, which closes open apps); pass `"slim": false` to
skip that. Every device is readied before any starts, so they begin together;
the result has `prep_ms` (slimming and readying) and, per device, `start_ms` / `end_ms` from that
common start and `steps_ms`.

## Install

SimDeck ships as a macOS app through Homebrew:

```bash
brew install --cask cuongdq88/simdeck/simdeck
```

The cask pulls in `adb` and `ffmpeg`. The Android SDK (command-line tools +
`emulator`) and Xcode with a simulator runtime are prerequisites; the app offers
to install the SDK pieces on first run. See the [root README](../README.md) for
requirements, the MCP setup, troubleshooting and known limitations.

## Requirements

- macOS 12+ (universal build; Apple Silicon tested).
- Android: `sdkmanager`/`avdmanager` and the `emulator` binary; system images
  are installed from the app's SDK Manager.
- iOS: Xcode with at least one runtime. On Xcode 27, Device Hub may take over
  input; the tile offers a repair (restarts the simulator's apps).
- Recording: `ffmpeg` for `.mp4` output; grid recording on macOS is native and
  asks for the Screen Recording permission.

## Run

The app is a member of the repository's pub workspace, so resolve from the
repository root (needs the Flutter SDK):

```bash
flutter pub get
cd app
flutter run -d macos   # or windows / linux
```

Tests: `flutter test` here, or `dart run melos run test:flutter` from the root.

## Benchmark

`benchmark/bench.dart` measures the running app through its MCP server:
CPU and memory of the app and its child processes, stream FPS, recording
frame rate, MCP latency and `run_scenario` skew / overhead. Build and start a
release app, boot the devices, then for example:

```bash
cd app
dart run benchmark/bench.dart stream --devices "iPhone 17e,Pixel_7" --animate
dart run benchmark/bench.dart scenario --devices "iPhone 17e,Pixel_7" --runs 20
dart run benchmark/bench.dart record --quality high --animate --devices "iPhone 17e"
```

Each run prints and saves a JSON report under `benchmark/results/`
(ignored by git). The file header lists every case and option.
