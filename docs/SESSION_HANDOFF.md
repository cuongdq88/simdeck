# Session Handoff

Cập nhật: 2026-11-07 (Asia/Ho_Chi_Minh)

## Điểm vào để tiếp tục
- Hành động chính xác tiếp theo: nếu được yêu cầu, upload
  `SimDeck/build-release/SimDeck-1.0.0-macos-arm64.dmg` to a GitHub Release.
  Do not claim it is notarized; no Developer ID identity is installed.

## Trạng thái repo
- Nhánh: `simdeck/main` → `origin/main`; commit mới nhất `f2fd300`.
- DMG ignored by Git under `SimDeck/build-release/`; checkpoint edits in `docs/`
  are uncommitted.
- Commit gần đây: `5cbd839` (fix double-close + reconnect loop), `0013de0`
  (docs → `docs/`, `CLAUDE.md`, `AGENTS.md` gọn), `4928067` (reconnect khi adb
  restart), `8591523` (ghi nhận fix adb crash).
- Repo public: https://github.com/cuongdq88/simdeck.

## Việc đã xác minh
- Build Release **BUILD SUCCEEDED** 2026-11-05 16:05, arm64; app đã restart và chạy
  từ `SimDeck/build-release/Build/Products/Release/SimDeck.app`; 3 tile E1/E2/E3
  (Android 16) đều `streaming: true`.
- Build Release **BUILD SUCCEEDED** 2026-11-07, arm64. DMG checksum/content and
  ad-hoc app signature verified; SHA-256
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
- SD-012 grid recording (2026-11-09): Release **BUILD SUCCEEDED**; `record_grid` qua MCP
  ghi MP4 H.264: low → 720×440, 15 fps, 7.7 s; high → 2844×1742 (2× cửa sổ), ~30 fps.
  Frame trích ra cho thấy đúng cả cửa sổ (sidebar, top bar, panel thông báo, đồng hồ
  REC). Settings đổi quality → `gridQuality: high` trong `settings.json`, lần record
  sau dùng đúng high. Guard: đang record E1 thì `record_grid` trả "Stop the device
  recordings before recording the grid." Cửa sổ Recordings (film icon) liệt kê file với
  ngày + dung lượng và nút mở/Reveal/xoá. Đã trả quality về `standard`, xoá file test.

## Task đang mở
- Không có task in-progress.
- **SD-010** Scenarios (YAML, editor, runner) — Pending.
- **SD-014** MCP parity: 23/27 tool — xong nhóm thiết bị/ứng dụng (`get_spotlight`,
  `connect_device`, `pair_device`, `disconnect_device`, `record_device`, `install_app`,
  `launch_app`, `find_elements`, `tap {label}`, `record_grid`); còn `run_scenario`/
  `stop_scenario` (chờ SD-010), `set_slim`/`set_slim_mode`, `repair_input`
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
