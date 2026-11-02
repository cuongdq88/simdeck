# SimDeck agent instructions

Use SimDeck for every emulator and simulator action. **Never** start a device
with the `emulator` binary, `avdmanager`, Android Studio, or `xcrun simctl boot`
from your own shell: those open a separate emulator window that SimDeck cannot
adopt. Start it through SimDeck instead, which always boots headless and shows
the screen inside the app.

MCP endpoint: `http://127.0.0.1:8765/mcp` (`SIMDECK_MCP_PORT` overrides it).
If it is not reachable, launch SimDeck (`open -a SimDeck`) and retry.

## Workflow

1. `list_devices` — see what exists and what is running.
2. `get_device_catalogs` — pick an installed system image or hardware profile.
3. `create_avd {name, image}` or `create_simulator {name}` when needed.
4. `start_device {device, headless: true, stream: true}` — boots headless; the
   screen opens as a tile inside SimDeck. Use `stream: false` when you only
   need adb/simctl (e.g. to install an app) and do not need to look at it.
5. `tap`, `swipe`, `type_text`, `press_button` — input; confirm with
   `screenshot`.
6. `stop_device` or `delete_device` when done.

If a device already has a window because something else started it, stop it
(`stop_device`, or `adb emu kill`) and start it again through SimDeck.

## Shell-only agents

If the agent cannot speak MCP, use the bundled CLI, which talks to the same
server:

```bash
SimDeck/bin/simdeck list
SimDeck/bin/simdeck boot "Pixel_9_API_36"       # headless, no tile
SimDeck/bin/simdeck start "Pixel_9_API_36"      # headless + tile in SimDeck
SimDeck/bin/simdeck tap "Pixel_9_API_36" 0.5 0.5
SimDeck/bin/simdeck type "Pixel_9_API_36" "hello"
SimDeck/bin/simdeck screenshot "Pixel_9_API_36"
SimDeck/bin/simdeck stop "Pixel_9_API_36"
```

## Install and launch an app (via adb, on a SimDeck-booted device)

Once SimDeck booted the device, normal adb works on its serial (from
`list_devices`):

```bash
adb -s <serial> install -r app.apk
adb -s <serial> shell am start -n <package>/<activity>
```
