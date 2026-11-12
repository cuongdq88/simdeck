# Session Handoff

Cập nhật: 2026-11-10 (Asia/Ho_Chi_Minh)

## Điểm vào để tiếp tục
- Hành động chính xác tiếp theo: **SD-010 Scenarios, phần UI** — runner và
  `run_scenario` / `stop_scenario` đã xong (nhận JSON steps). Còn parser YAML đúng
  format bản cũ, editor có syntax highlight, panel tiến trình, gợi ý YAML.
- Release 1.0.0 đã publish (tag `simdeck-v1.0.0` + DMG). Đừng nói bản này đã
  notarize: chỉ ad-hoc signed, chưa có Developer ID.

## Trạng thái repo
- Nhánh: `master` → `origin/master`; commit mới nhất `9951c97`. Remote chỉ còn
  `master` và đó là default branch.
- DMG ignored by Git under `SimDeck/build-release/`; docs đã commit và push.
- Commit gần đây: `9951c97` (docs trỏ `master`), `5dcca85` (grid recording),
  `f8bd512` (`find_elements`, `tap {label}`), `fa99b6a` (wireless/install/launch/
  record tool), `1c116c1` + `783158e` + `9a69444` (notification panel),
  `a8b44b8` (notifications + Settings).
- Repo public: https://github.com/cuongdq88/simdeck.
- Working tree: `AGENTS.md` bị environment sửa và `third_party/*` deleted — không
  phải việc của dự án, không stage.

## Việc đã xác minh
- Scenario runner (2026-11-12): Release **BUILD SUCCEEDED**; MCP có 25 tool. Chạy
  `run_scenario` trên E1 + iPhone 17 song song: cả hai `start_ms: 0`, cùng `end_ms`;
  tap theo label (`Network & internet`), `assert_visible`/`assert_not_visible` (cả
  pass lẫn fail), swipe `until: About` (6 lần), `type` vào ô Search Settings,
  `if_visible` bỏ bước, `repeat: 3`, `launch` với `android`/`ios` riêng, `clear_state`,
  device chưa stream (E2) tự mở stream với `prep_ms: 4141`, và `stop_scenario` dừng
  giữa `wait` 15 s (kết quả `error: "Stopped"`). Bước label trên iOS báo lỗi rõ ràng;
  bước sai (`x: 2`) bị chặn trước khi máy nào chạy.
- Build Release **BUILD SUCCEEDED** 2026-11-05 16:05, arm64; app đã restart và chạy
  từ `SimDeck/build-release/Build/Products/Release/SimDeck.app`; 3 tile E1/E2/E3
  (Android 16) đều `streaming: true`.
- Build Release **BUILD SUCCEEDED** 2026-11-07, arm64. DMG của ngày đó chỉ là bản
  thử (không phải bản phát hành); checksum/content và chữ ký ad-hoc đã kiểm, SHA-256
  `48f85721575ec3b53d5443bd2da1f3d7604fdf13e775ed12e001c39efb82bf33`.
- Crash report 16:23/20:10: `ProcessRunner.runSync` → `readDataToEndOfFile()`
  ném ObjC exception khi pipe adb đóng → `SIGABRT`. Đã fix bằng `readAll`
  (`read(upToCount:)` + catch); test `adb kill-server` khi đang stream, app sống.
- Stream đứt lặp (2026-11-05): fixed double-close video fd (`ScrcpySession.stop()`
  không còn `close`, reader tự close sau khi clear `videoFD` dưới lock), thêm log
  `SimDeck scrcpy end serial=… count=… errno=… serverAlive=… frames=…`, và chặn
  reconnect vô hạn (`streamLiveSince` ≥30 s mới reset retry; bỏ status từ session
  đã bị thay thế). Verify: `xcodebuild` Debug + Release đều BUILD SUCCEEDED.
- MCP `POST /mcp` initialize → 200.
- Task tracker: `TASK.md` (đã xong / hoãn / tiếp theo).
- SD-009 + SD-015 (2026-11-08): build Release **BUILD SUCCEEDED**, không warning;
  chạy app thật và chụp màn hình xác minh: Settings sheet render đủ 3 nhóm, toggle
  headless/frame đọc đúng `settings.json`, badge chuông + popover Notifications
  (thứ tự mới→cũ, Clear, empty state), bấm 1 dòng hiện lại thông báo; đặt
  `recordingFolder` = `/tmp/simdeck-shots` → `simdeck screenshot E1` ghi PNG đúng
  thư mục đó. Chưa test đường record video vào thư mục tuỳ chọn (dùng chung
  `CaptureService.directory`) và nút `Choose…` (NSOpenPanel chuẩn).
- SD-014 (2026-11-08): `tools/list` trả 21 tool; chạy thật trên E1: `launch_app`
  mở Settings, `launch_app` sai package trả lỗi rõ, `install_app` sai đường dẫn trả
  lỗi adb, `record_device` start/stop ghi MP4 44 KB, `get_spotlight` trả layout +
  stream; `connect_device`/`disconnect_device` trả `connected: false` khi cổng từ chối.
  Chưa test `pair_device` (cần thiết bị Wi-Fi thật) và `install_app` thành công bằng
  file APK thật.
- SD-014 `find_elements` + `tap {label}` (2026-11-09): `tools/list` = 22 tool; trên E1
  `find_elements` trả 14 phần tử Settings (label/role/center/frame chuẩn hoá),
  `tap {"label":"Network & internet"}` mở đúng màn Network & internet (screenshot),
  nhãn không tồn tại với `timeout_ms:1200` trả `No element matches …` sau ~2 s;
  `tap {x,y}` vẫn chạy; iOS simulator trả lỗi "supports Android devices only".
- Boot/stream (2026-11-11): mở stream ngay sau khi boot từng báo "The device did not
  finish booting. adb: device offline" vì `adb shell` một phát dài fail khi adb còn
  offline. Thay bằng poll `getprop sys.boot_completed` mỗi 2 s (timeout 300 s):
  tạo AVD mới + `start_device {stream:true}` → streaming trong 31 s; chạy 4 emulator
  cùng lúc → 75 s, không lỗi.
- Tên thiết bị có dấu cách (2026-11-11): `create_avd {"name":"Space Test"}` tạo
  `Space_Test.avd` với `avd.ini.displayname=Space Test`; `list_devices` trả
  `name: "Space Test"`, `id: android:Space_Test`; boot headless OK, screenshot
  `Space_Test-…png`; tạo qua sheet (⌘N) "My Phone 02" → `My_Phone_02`; iOS
  `create_simulator {"name":"iPhone Test 11"}` OK. Đã xoá AVD/simulator/file test.
  AVD có dấu cách trên đĩa (tạo tay) làm `emulator` exit 139 — đó là lý do tách
  display name khỏi tên file.
- Release 1.0.0 (2026-11-09): build Release từ `5dcca85`, DMG có app + link
  Applications + `LICENSE` + `third_party/`, `hdiutil verify` VALID, mount thử OK;
  tag `simdeck-v1.0.0` push lên `cuongdq88/simdeck` và GitHub Release kèm asset
  `SimDeck-1.0.0-macos-arm64.dmg` (4,534,797 bytes, SHA-256
  `11021a3d…76885`). Branch `main` đổi tên thành `master`, thành default branch.
- SD-012 grid recording (2026-11-09): Release **BUILD SUCCEEDED**; `record_grid` qua MCP
  ghi MP4 H.264: low → 720×440, 15 fps, 7.7 s; high → 2844×1742 (2× cửa sổ), ~30 fps.
  Frame trích ra cho thấy đúng cả cửa sổ (sidebar, top bar, panel thông báo, đồng hồ
  REC). Settings đổi quality → `gridQuality: high` trong `settings.json`, lần record
  sau dùng đúng high. Guard: đang record E1 thì `record_grid` trả "Stop the device
  recordings before recording the grid." Cửa sổ Recordings (film icon) liệt kê file với
  ngày + dung lượng và nút mở/Reveal/xoá. Đã trả quality về `standard`, xoá file test.

- Tạo iOS simulator (2026-11-12): máy có 2 runtime cùng tên "iOS 27.2" nhưng
  `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4` chỉ hỗ trợ "iPhone Duo"
  (`supportedDeviceTypes`), nên chọn runtime đầu tiên làm mọi loại máy khác fail
  `Incompatible device` (code 403) — đây là lý do không tạo được iPhone 17 Pro /
  Pro Max. Fix: `SimulatorRuntime.supportedDeviceTypes` + `SimctlService.runtime(for:in:)`;
  sheet chỉ liệt kê runtime tương thích và tự chọn lại khi đổi Device; MCP
  `create_simulator` lọc/validate và báo `Runtime … cannot boot …`. Verify: MCP tạo
  `Check Pro`/`Check Pro Max`/`Check Default` trên `iOS-27-2`; runtime không tương
  thích trả lỗi rõ; sheet (⌘N) chọn iPhone 17 Pro → Runtime còn 1 mục, Create bật,
  tạo `UI Check Pro` đúng runtime `iOS-27-2`; đã xoá hết simulator test.
- iPhone thật không stream/record (2026-11-12): `🅲🅳 iPro` (iPhone 13 Pro, iOS 27.2)
  đang kết nối Wi-Fi — `devicectl` báo `transportType: localNetwork`,
  `tunnelState: disconnected`, `xctrace` xếp offline; `AVCaptureDevice` discovery
  `.muxed` trả 0 thiết bị. Đường capture hiện tại là CoreMediaIO USB-only nên cần
  cáp USB + mở khoá máy; chưa thể xác minh end-to-end.

- Tiếng trong tile Android (2026-11-12): Release **BUILD SUCCEEDED**. scrcpy chạy
  `audio=true audio_codec=raw`; header audio chỉ tới sau khi capture khởi động (đo
  được lần đầu >5 s rồi mới có), nên đọc codec id ở luồng riêng, chờ tới 30 s.
  Verify trên E1/E3: log `SimDeck audio start serial=emulator-5554/5556`, qemu có
  `-no-audio`, CoreAudio `setPlayState Started Output {BuiltInSpeakerDevice}` +
  `output_running: true`; đóng E3 rồi E1 → `setPlayState Stopped`,
  `output_running: false`, app sống, `frames=146/55`. Probe server độc lập xác nhận
  gói raw 4096 byte, codec id `00 72 61 77`.
- iPhone thật Wi-Fi (2026-11-12): sidebar hiện "USB required" và nút Stream xám
  (tooltip "Connect via USB to stream"), menu chuột phải Stream bị disable;
  `start_device {"device":"ios-device:00008110-…"}` trả "… is not connected by USB
  cable (or is locked). Streaming over Wi-Fi is not supported: …".

## Task đang mở
- Không có task in-progress.
- **SD-010** Scenarios (YAML, editor, panel) — runner + MCP tools xong, UI Pending.
- **SD-014** MCP parity: bản cũ 27 tool → bản Swift 25 tool (thêm `stop_device` mà
  bản cũ không có). Đã xong nhóm thiết bị/ứng dụng (`get_spotlight`, `connect_device`,
  `pair_device`, `disconnect_device`, `record_device`, `install_app`, `launch_app`,
  `find_elements`, `tap {label}`, `record_grid`, `run_scenario`/`stop_scenario`);
  còn 3 tool: `set_slim`/`set_slim_mode`, `repair_input`
  (iOS simulator) — Pending.
- **SD-016** Agent mode không cửa sổ — Blocked (SwiftUI SceneBuilder không bỏ được
  `WindowGroup`; hiện auto-launch cửa sổ SimDeck bình thường).
- **SD-018** Tương tác iPhone thật (hiện view-only) — Blocked (chưa có thiết bị).
- File cần xem: `TASK.md`, `PROJECT_STATE.md`, `SimDeck/Sources/App/AppModel.swift`,
  `SimDeck/Sources/App/SimDeckApp.swift`, `SimDeck/Sources/MCP/McpServer.swift`,
  `SimDeck/Sources/UI/`, `SimDeck/bin/`, `SimDeck/AGENT.md`.

## Chặn / rủi ro
- Ad-hoc signing → Gatekeeper; cần `xattr -dr com.apple.quarantine` hoặc notarize.
- Build arm64-only; iOS cần Xcode, Android cần SDK/emulator trên máy người dùng.
- Chưa test iPhone thật; Dock icon có thể cần xoá cache iconservices.
- Tiếng trong tile: emulator do SimDeck bật im khi không mở tile (kể cả
  `stream:false`); emulator đang chạy sẵn do tool khác bật sẽ nghe đôi; điện thoại
  Android thật vẫn phát loa ngoài.
- iPhone thật chỉ stream/record được qua USB (CoreMediaIO `.muxed`); máy kết nối
  Wi-Fi vẫn hiện trong sidebar nhưng mở tile sẽ lỗi "No capture device".
- Lịch sử git còn commit bản Flutter cũ.

## Lệnh an toàn để chạy lại
```bash
cd SimDeck
xcodegen generate
xcodebuild -project SimDeck.xcodeproj -scheme SimDeck \
  -configuration Release -derivedDataPath build-release build
open build-release/Build/Products/Release/SimDeck.app

# MCP sống?
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
  http://127.0.0.1:8765/mcp

git status --short --branch
```

## Ngữ cảnh quan trọng
- Thiết kế đã duyệt: SimUtil 1:1; không tự đổi UI nếu không có lý do/đồng ý.
- Đã chốt: scrcpy thay gRPC; headless mặc định cho agent; không `-no-audio`; MCP + CLI
  dùng chung hành vi; stop phải diệt qemu kể cả khi adb mất kết nối.
- License MIT © 2026 cuongdq88; notices ở `third_party/` (SimUtil, emu, serve-sim,
  scrcpy). `AGENTS.md` của người dùng không được sửa/commit khi chưa có yêu cầu.
- adb: SimDeck dùng `~/Library/Android/sdk/platform-tools/adb` (37.0.1). Ngày
  2026-11-02 đã kill adb server rác cổng 5047 và symlink `/opt/homebrew/bin/adb`
  sang SDK 37. Nếu stream lại đứt hàng loạt, kiểm tra
  `grep "killed by remote request" "$TMPDIR/adb.501.log"` trước — đó là dấu hiệu
  một tool khác gọi kill-server, không phải lỗi scrcpy.
- **Nguyên nhân gốc đã xác minh (2026-11-05)**: `adb kill-server` chạy ngay sau khi
  Gradle build của project Android khác kết thúc. 5/5 mốc khớp trong ~1 s
  (15:14:45→:46.9, 15:19:55→:55.8, 15:28:09→:09.7, 15:31:50.1→:50.7,
  15:32:24.5→:25.5). Nguồn: `rangbox` (Godot Android, Gradle 8.11.1 daemon) và
  `mutil-languages/xiao-zhu/android` (Gradle 9.8.2). SimDeck không chứa chuỗi
  `kill-server` trong binary. Các cú lẻ 15:24:40/15:25:05/15:25:18/15:54:52 chưa
  khớp build. Muốn hết đứt: chặn `kill-server` trong chain build/deploy đó, hoặc
  build các project ấy với adb server riêng; bản SimDeck mới chỉ chống chịu.
