# Project State

Cập nhật: 2026-11-02 15:55 (Asia/Ho_Chi_Minh)

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
- Nhánh `simdeck/main` → `origin/main`; commit mới nhất `6792765`.
- Repo: https://github.com/cuongdq88/simdeck (public).
- Working tree: `AGENTS.md` bị sửa bởi người dùng (chưa commit); ngoài ra sạch trước
  khi thêm hai file state này.
- App Release đang chạy từ `SimDeck/build-release/Build/Products/Release/SimDeck.app`.
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
  - Toast in-app, icon app (asset catalog + `AppIcon.icns`), MCP 14 tool, CLI, bridge
    OpenCode.
  - Crash `SIGABRT` khi adb server chết (pipe stderr đóng) đã fix: `ProcessRunner`
    dùng `read(upToCount:)` thay `readDataToEndOfFile()`; đã test `adb kill-server`
    khi đang stream, app vẫn sống.
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
- Build Release: 2026-11-02 15:19, `xcodebuild -project SimDeck.xcodeproj -scheme SimDeck
  -configuration Release -derivedDataPath build-release build` → **BUILD SUCCEEDED**, arm64.
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
- `AGENTS.md` đang có thay đổi chưa commit của người dùng.
- adb server 5037 từng bị client adb khác gọi `kill-server` (log
  `adb server killed by remote request`), làm đứt mọi stream scrcpy. Đã kill server
  rác cổng 5047 và symlink `/opt/homebrew/bin/adb` → SDK 37.0.1 (2026-11-02). Nếu
  `brew upgrade --cask android-platform-tools` chạy lại, symlink có thể bị ghi đè:
  `ln -sfn ~/Library/Android/sdk/platform-tools/adb /opt/homebrew/bin/adb`.

## Mốc tiếp theo
- Không có việc đang dở. Chờ người dùng chọn: Notification Center trong app (SD-009)
  hoặc đóng gói DMG/notarize (SD-017). Không tự bắt đầu mục đã hoãn.
