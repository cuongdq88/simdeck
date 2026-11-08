# Project State

Cập nhật: 2026-11-07 (Asia/Ho_Chi_Minh)

## Phạm vi & yêu cầu
- Mục tiêu: **SimDeck** — app macOS native SwiftUI để tạo/chạy/stream/điều khiển
  Android emulator, iOS simulator và thiết bị iOS thật trong một cửa sổ.
- Ràng buộc đã chốt:
  - Không Flutter, không `simutil_*`, không Rust `emu`; toàn bộ app nằm trong `SimDeck/`.
  - Vendor `scrcpy-server`; Android stream bằng scrcpy, chạy được emulator headless.
  - Giữ thiết kế SimUtil 1:1: page `#0B0C0E`, sidebar `#111215`, panel `#17181B`,
    accent `#2DD4BF`, Menlo, radius 12, sidebar 288 px, top bar 52 px.
  - Agent dùng MCP (`http://127.0.0.1:8765/mcp`) hoặc CLI; boot headless, không mở
    cửa sổ emulator riêng.
  - MIT © 2026 cuongdq88; repo public.

## Trạng thái đã xác minh
- Nhánh `simdeck/main` → `origin/main`; commit mới nhất `f2fd300`.
- Repo: https://github.com/cuongdq88/simdeck (public).
- Working tree sạch.
- App Release đang chạy từ `SimDeck/build-release/Build/Products/Release/SimDeck.app`
  (build 2026-11-05 16:05, PID mới sau khi restart).
- MCP `initialize` trả HTTP 200.
- Đã chạy được (kiểm tra thủ công):
  - Danh sách thiết bị gộp adb + qemu process + iOS simulator; stop diệt cả qemu khi
    adb mất kết nối.
  - Tạo/sửa/xoá AVD bằng `config.ini` trực tiếp (không cần Java/avdmanager); SDK
    manager, logcat, Wi-Fi pairing.
  - Android: boot headless, scrcpy stream vào tile, tap/type/rotate, screenshot/record, stop.
  - iOS simulator: capture CoreSimulator/SimulatorKit, HID, xoay, tile full-width/3 cột,
    drag-reorder, spotlight.
  - iOS thật: `devicectl` + CoreMediaIO view-only (parser kiểm bằng JSON mẫu; chưa có
    máy thật để test).
  - Toast in-app, icon app (asset catalog + `AppIcon.icns`), MCP 21 tool, CLI, bridge
    OpenCode.
  - SD-009 Notification Center: `AppModel.notices` (50 toast gần nhất, chỉ trong
    phiên) + chuông có badge chưa đọc trên top bar; popover có Clear, bấm dòng để
    hiện lại toast. SD-015 Settings sheet (gear/⌘,): headless mặc định,
    `frameDefault`, layout mặc định, `recordingFolder` — lưu trong `settings.json`;
    `CaptureService.directory` dùng `folderOverride` (đã xác minh bằng screenshot
    E1 ghi vào thư mục tuỳ chọn).
  - Crash `SIGABRT` khi adb server chết (pipe stderr đóng) đã fix: `ProcessRunner`
    dùng `read(upToCount:)` thay `readDataToEndOfFile()`; đã test `adb kill-server`
    khi đang stream, app vẫn sống.
  - Stream Android đứt lặp: `ScrcpySession.stop()` và reader cùng `close()` một fd
    (double-close) → có thể đóng nhầm socket của tile khác khi fd được tái sử dụng.
    Reader giờ giữ quyền close, `stop()` chỉ `shutdown` dưới lock; mỗi lần recv lỗi
    ghi `errno`/`serverAlive`/`frames` vào `NSLog` (`SimDeck scrcpy end …`).
  - Vòng reconnect: `AppModel` reset `streamRetries` ngay khi `.live` nên lặp vô hạn.
    Giờ chỉ reset khi stream sống ≥ 30 s; status từ session đã bị thay thế bị bỏ qua.
  - Đã build Release + restart app bản mới, mở lại 3 tile E1/E2/E3 (đều `streaming: true`).
- Chưa xác minh: các mục pending trong `TASK.md`; iPhone thật; build universal
  (hiện chỉ arm64).

## Quyết định kiến trúc
- SwiftUI thuần + XcodeGen (`SimDeck/project.yml`), không phụ thuộc package ngoài.
- Android stream qua scrcpy server vendored: giữ stdin pipe để server không EOF, retry
  `adb forward`, push lại jar trước mỗi lần start.
- AVD ghi trực tiếp `config.ini`/`.ini`, bảo toàn key/comment lạ.
- Boot agent mặc định headless: `-no-window -no-boot-anim -gpu host`; `stream: true`
  thêm tile. Không dùng `-no-audio`.
- Stop: process đã giữ → `adb emu kill` → quét `ps` qemu (`-avd X`/`@X`) → SIGTERM →
  SIGKILL sau ~3 s.
- MCP là giao diện chính; CLI và bridge stdio dùng chung hành vi, tự bật app nếu chưa chạy.
- Grid: số cột theo bề rộng (>=300 pt): 1 = full width, 2 = 2 cột, 3 = 3 cột, 4+ xuống hàng.
- Identity sidebar `groupID:deviceKey`; grid `.id(device.key)`; `VideoLayerView.updateNSView`
  gắn lại layer khi sink đổi.
- App ad-hoc signed; entitlements có `disable-library-validation` để load private framework.

## Kiểm chứng
- Build Release: 2026-11-05 16:05, `xcodebuild -project SimDeck.xcodeproj -scheme SimDeck
  -configuration Release -derivedDataPath build-release build` → **BUILD SUCCEEDED**, arm64.
- Build Release 2026-11-07 → **BUILD SUCCEEDED**, arm64. Verified DMG:
  `SimDeck/build-release/SimDeck-1.0.0-macos-arm64.dmg`, with app, `LICENSE`,
  `third_party/`, and Applications link. SHA-256:
  `48f85721575ec3b53d5443bd2da1f3d7604fdf13e775ed12e001c39efb82bf33`.
  DMG checksum, contents, and ad-hoc app signature verified.
- Build Debug: 2026-11-05 15:48 → **BUILD SUCCEEDED**.
- Build Release 2026-11-08 (SD-009/SD-015) → **BUILD SUCCEEDED**, arm64, không warning.
- MCP `initialize`: 2026-11-02, HTTP 200.
- Không có test target tự động; kiểm tra UI/stream thủ công.

## Rủi ro / chặn
- Ad-hoc signature → máy khác phải `xattr -dr com.apple.quarantine`; muốn cài sạch cần
  Developer ID + notarize.
- Build hiện chỉ arm64; muốn chạy Intel cần `ARCHS="arm64 x86_64"`.
- iOS cần Xcode + runtime; Android cần SDK/platform-tools/emulator; app không tự cài.
- Dock icon có thể cần xoá cache iconservices; style macOS “Clear Dark” làm icon đơn sắc.
- Chưa test iPhone thật.
- Lịch sử git còn commit của bản Flutter cũ (code đã xoá nhưng history vẫn còn).
- adb server 5037 bị kill bởi **build Gradle của project khác** (2026-11-05 đã xác
  minh): mỗi lần build xong thì `adb kill-server` chạy trong ~1 s, khớp 5/5 mốc:
  15:14:45→:46.9, 15:19:55→:55.8, 15:28:09→:09.7, 15:31:50.1→:50.7, 15:32:24.5→:25.5.
  Nguồn: Gradle daemon `rangbox` (Godot Android, Gradle 8.11.1) và
  `mutil-languages/xiao-zhu/android` (Gradle 9.8.2). SimDeck không gọi `kill-server`
  (binary không chứa chuỗi này). Một số cú kill lẻ (15:24:40/15:25:05/15:25:18/15:54:52)
  chưa khớp build — nghi lệnh thủ công hoặc agent khác.
- Hệ quả: build của các project Android khác sẽ luôn làm đứt mọi stream scrcpy. Bản mới
  tự reconnect có giới hạn nên chịu được, nhưng muốn hết hẳn phải chặn `kill-server`
  từ quy trình build đó. Đã kill server rác cổng 5047 và symlink
  `/opt/homebrew/bin/adb` → SDK 37.0.1 (2026-11-02). Nếu
  `brew upgrade --cask android-platform-tools` chạy lại, symlink có thể bị ghi đè:
  `ln -sfn ~/Library/Android/sdk/platform-tools/adb /opt/homebrew/bin/adb`.

## Mốc tiếp theo
- DMG is available for upload if the user accepts ad-hoc signing. No Developer ID
  identity is installed, so notarization and Gatekeeper validation remain pending
  for a public end-user release.
- Việc nên làm khi có thời gian: chặn `adb kill-server` trong quy trình build của
  `rangbox` / `xiao-zhu` (hoặc tách adb server) để stream không bị đứt định kỳ.
