# SimDeck (SwiftUI)

A native macOS rewrite of SimDeck: create, run, stream and delete Android
emulators and iOS simulators. It shares **no code** with the Flutter app in
`app/`, the `packages/simutil_*` libraries or the Rust `emu` helper — the only
external pieces are the platform tools themselves (`adb`, `emulator`,
`xcrun simctl`) and the bundled `scrcpy-server`.

The UI is a one-to-one port of SimUtil's design system (tokens, sidebar, top
bar, stream tiles), so both shells look the same.

## Requirements

- macOS 14 or newer.
- Xcode 27 with at least one installed simulator runtime.
- Android SDK with `platform-tools` and `emulator` (`ANDROID_HOME`,
  `ANDROID_SDK_ROOT`, `~/Library/Android/sdk` or the Homebrew command-line
  tools are probed in that order).
- No Java and no `avdmanager`: AVDs are written directly as `config.ini` +
  `<name>.ini`, and system images are found by scanning the SDK.

## Build and run

```bash
cd SimDeck
xcodegen generate                # project.yml -> SimDeck.xcodeproj
xcodebuild -project SimDeck.xcodeproj -scheme SimDeck \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/SimDeck.app
```

The app loads Xcode's private `CoreSimulator` / `SimulatorKit` frameworks at
runtime for the simulator screen and input, so a signed build needs the
`com.apple.security.cs.disable-library-validation` entitlement. It is set in
`Config/SimDeck.entitlements`.

## What it does

| Feature | How |
| --- | --- |
| Device list | AVDs from `~/.android/avd`, running emulators and USB devices from `adb devices`, simulators from `xcrun simctl list` |
| Android streaming | own scrcpy client: pushes `scrcpy-server`, `adb forward`, parses the 4.x protocol, decodes H.264 with VideoToolbox |
| Android input | scrcpy control socket (touch, keys, text, rotate) |
| iOS streaming | private `SimulatorKit` framebuffer callbacks → `AVSampleBufferDisplayLayer` |
| iOS device frame | Xcode's DeviceKit chrome (`chrome.json` + PDFs): composite or nine-slice bezel, framebuffer mask, clickable side buttons |
| iOS input | legacy Indigo HID client plus a GSEvent orientation message for rotate |
| Create AVD | writes `config.ini` from a built-in hardware profile catalog |
| Edit AVD | RAM, data size, back camera, orientation, keyboard and SD card; every other key and comment is preserved |
| Launch options | per device: headless, cold boot (no snapshot), camera source (restarts the emulator), restart |
| Settings | `~/Library/Application Support/SimDeck/settings.json` (headless, cold boot, camera, frame) |
| Create simulator | `xcrun simctl create` |
| Screenshots | `adb exec-out screencap` / `simctl io screenshot`, saved to `~/Pictures/SimDeck` |
| Recording | `adb shell screenrecord` (pulled back) / `simctl io recordVideo`, with a REC clock in the tile |
| SDK Manager | installed images by scanning the SDK; downloads and licence acceptance through `sdkmanager` |
| MCP server | loopback Streamable HTTP at `http://127.0.0.1:8765/mcp` (14 tools: list/create/start/stop/delete, tap, swipe, type, buttons, screenshot) |
| Layouts | adaptive grid, or a spotlight with the rest in a strip on the right / bottom; the choice and focus persist |
| Reordering | drag a tile by its header onto another to move it in the grid |
| Wipe / delete | file-level wipe, guard against shared AVD directories, running devices and in-use images |

## Layout

| Path | Contents |
| --- | --- |
| `Sources/App` | `AppModel` (state, streams, actions) and the `@main` app |
| `Sources/Design` | SimUtil's tokens and components |
| `Sources/UI` | sidebar, top bar, grid, tiles, device frame, create sheet |
| `Sources/Android` | SDK paths, AVD store/creator, images, profiles, adb, emulator control, deletion guard, SDK Manager |
| `Sources/Apple` | `simctl` service |
| `Sources/Capture` | screenshots and screen recordings |
| `Sources/MCP` | loopback MCP server and tools |
| `Sources/Streaming` | scrcpy protocol/session, H.264 decoder, simulator capture and HID, video sink/layer |
| `Resources` | bundled `scrcpy-server` (Genymobile/scrcpy, Apache-2.0) and the logo |

## Debug

- `SIMDECK_OPEN_STREAMS=1` opens a stream for every running device at launch;
  `SIMDECK_OPEN_STREAMS=first` opens only the first one.
- `SIMDECK_SHOW_SDK=1` opens the SDK Manager at launch.
  Use `open --env KEY=VALUE SimDeck.app`.

## MCP

The app serves MCP over HTTP on loopback while it runs
(`SIMDECK_MCP_PORT` changes the port). Add it to an agent:

```json
{ "mcp": { "simdeck": { "type": "remote", "url": "http://127.0.0.1:8765/mcp" } } }
```

Tools: `list_devices`, `get_device_catalogs`, `create_avd`,
`create_simulator`, `start_device`, `stream_device`, `stop_device`,
`shutdown_device`, `delete_device`, `tap`, `swipe`, `type_text`,
`press_button`, `screenshot`.

## Not ported yet

Emulator gRPC video (Android uses scrcpy, which works headless too), Wi-Fi
pairing, logcat, scenarios, the plugin registry, physical iOS devices, grid
recording, and spotlight layouts with drag reordering.
