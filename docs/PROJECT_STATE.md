# Project State

Cập nhật: 2026-11-10 (Asia/Ho_Chi_Minh)

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
- Nhánh `master` → `origin/master`; commit mới nhất `9951c97`. Remote chỉ còn
  `master` và đó là default branch (đã đổi tên từ `main`).
- Repo: https://github.com/cuongdq88/simdeck (public).
- Working tree **không** sạch: `AGENTS.md` bị environment sửa và `third_party/*`
  đang ở trạng thái deleted — cả hai không phải thay đổi của dự án, không stage.
- Release `simdeck-v1.0.0` (tag trỏ `5dcca85`) đã publish kèm
  `SimDeck-1.0.0-macos-arm64.dmg`, 4,534,797 bytes, ad-hoc signed, SHA-256
  `11021a3d971a86c796279e9fd133584b472aa4aec2a5202a8fe32ffc67376885`:
  https://github.com/cuongdq88/simdeck/releases/tag/simdeck-v1.0.0
- App Release đang chạy từ `SimDeck/build-release/Build/Products/Release/SimDeck.app`
  (build 2026-11-09 18:34 từ `5dcca85`).
- MCP `initialize` trả HTTP 200.
- Đã chạy được (kiểm tra thủ công):
  - Danh sách thiết bị gộp adb + qemu process + iOS simulator; stop diệt cả qemu khi
    adb mất kết nối.
  - Tạo/sửa/xoá AVD bằng `config.ini` trực tiếp (không cần Java/avdmanager); SDK
    manager, logcat, Wi-Fi pairing.
  - Android: boot headless, scrcpy stream vào tile, tap/type/rotate, screenshot/record, stop.
    Tiếng của thiết bị phát trong tile (PCM raw + AVAudioEngine); emulator do
    SimDeck bật chạy `-no-audio` nên không nghe đôi.
  - iOS simulator: capture CoreSimulator/SimulatorKit, HID, xoay, tile full-width/3 cột,
    drag-reorder, spotlight. Tạo máy lọc theo `supportedDeviceTypes` của runtime
    (runtime cài cho một loại máy, ví dụ "iPhone Duo", không dùng cho máy khác được).
  - iOS thật: `devicectl` + CoreMediaIO view-only (parser kiểm bằng JSON mẫu; chưa có
    máy thật để test). Capture là USB-only: máy chỉ kết nối Wi-Fi vẫn hiện trong danh
    sách nhưng không có capture device để stream/record.
  - Toast in-app, icon app (asset catalog + `AppIcon.icns`), MCP 23 tool, CLI, bridge
    OpenCode.
  - SD-012 Grid recording: ScreenCaptureKit quay cả cửa sổ ra H.264 MP4 (4 mức chất
    lượng 15/24/30/60 fps, 720p/1280 px/full), REC + đồng hồ trên top bar, cửa sổ
    Recordings mở/Reveal/xoá file trong thư mục capture.
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
- Chưa xác minh: các mục pending trong `TASK.md` (scenarios); iPhone thật; build
  universal (hiện chỉ arm64).

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
- Build Release 2026-11-07 → **BUILD SUCCEEDED**, arm64. DMG tạo ngày đó (SHA-256
  `48f85721…bf33`) chỉ là bản thử, **không** phải bản phát hành.
- Build Release 2026-11-09 (SD-012) → **BUILD SUCCEEDED**, arm64. DMG phát hành:
  `SimDeck/build-release/SimDeck-1.0.0-macos-arm64.dmg` gồm `SimDeck.app`,
  `LICENSE`, `third_party/` (5 file) và link Applications; `hdiutil verify` VALID,
  mount thử liệt kê đúng, app ký ad-hoc. SHA-256
  `11021a3d971a86c796279e9fd133584b472aa4aec2a5202a8fe32ffc67376885`.
- GitHub Release `simdeck-v1.0.0` (2026-11-09): asset
  `SimDeck-1.0.0-macos-arm64.dmg` state `uploaded`; sau đó branch `main` đổi tên
  thành `master` và thành default branch.
- MCP `tools/list` (2026-11-09): 23 tool.
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
- **SD-010 Scenarios**: YAML đúng format bản cũ, editor, runner song song nhiều máy,
  panel bên phải; sau đó mở khoá `run_scenario` / `stop_scenario` (SD-019).
- Notarize: chưa có Developer ID, nên bản phát hành vẫn ad-hoc và cần
  `xattr -dr com.apple.quarantine`.
- Việc nên làm khi có thời gian: chặn `adb kill-server` trong quy trình build của
  `rangbox` / `xiao-zhu` (hoặc tách adb server) để stream không bị đứt định kỳ.
