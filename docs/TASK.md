# TASK

App SwiftUI trong `SimDeck/` **là toàn bộ app**; bản Flutter, `packages/` và các
workflow/script/packaging/docs cũ của nó đã bị xoá khỏi repo.

## Trạng thái hiện tại (2026-11-05)

- **Repo**: https://github.com/cuongdq88/simdeck — **PUBLIC**, nhánh `main`.
- **App**: SwiftUI native trong `SimDeck/`, build Release OK, icon riêng
  (`Assets.xcassets` + `AppIcon.icns`), logo sidebar mới.
- **Agent**: MCP loopback `http://127.0.0.1:8765/mcp`, CLI `SimDeck/bin/simdeck`,
  bridge stdio `SimDeck/bin/simdeck-mcp` (OpenCode dùng bridge, tự bật app).
  `start_device` luôn boot headless — không có cửa sổ emulator riêng.
- **License**: MIT © 2026 cuongdq88 (`LICENSE`), notices third-party trong
  `third_party/` (SimUtil MIT, emu MIT, serve-sim Apache-2.0, scrcpy Apache-2.0).
- **Chạy nhanh**:
  ```bash
  cd SimDeck
  xcodegen generate
  xcodebuild -project SimDeck.xcodeproj -scheme SimDeck \
    -configuration Release -derivedDataPath build-release build
  open build-release/Build/Products/Release/SimDeck.app
  ```
- **Lưu ý**: app ad-hoc signed → máy khác cần
  `xattr -dr com.apple.quarantine SimDeck.app`; Dock icon có thể cần xoá cache
  `~/Library/Caches/com.apple.iconservices.store` + `killall Dock`; macOS icon
  style “Clear Dark” làm icon hiển thị đơn sắc (đổi sang Default để thấy màu).

## Tiếp theo

- [ ] **SD-010 — Scenarios**: YAML, editor, runner + panel bên phải
- [ ] **SD-011 — Plugin registry** (`~/.simutil/settings.yaml`) + chạy lệnh ngoài
- [ ] **SD-012 — Grid recording**: ScreenCaptureKit + chọn chất lượng + danh sách recording đã lưu
- [ ] **SD-013 — Emulator gRPC video** (tuỳ chọn; scrcpy hiện đã phủ, chạy cả headless)
- [ ] **SD-014 — MCP tool parity**: bổ sung các tool còn thiếu của bản Flutter (27 tool)
- [ ] **SD-016 — Agent mode không cửa sổ**: `SIMDECK_AGENT=1` (accessory, không WindowGroup) hoặc target CLI `simdeck-mcp` cho CI
- [ ] **SD-017 — Đóng gói phát hành**: script tạo DMG (kèm `LICENSE` + `third_party/`), ký
      Developer ID + notarize để người khác cài không bị Gatekeeper chặn; cask Homebrew.
      DMG arm64 ad-hoc đã build ngày 2026-11-07 để upload thử nghiệm; mục này vẫn pending
      Developer ID/notarization, script phát hành và cask.
- [ ] **SD-018 — iOS thật, tương tác**: hiện view-only; thêm input khi có thiết bị thật

## Đã xong

- [x] Thiết bị: list/create/start/stop/wipe/delete, search, guards
- [x] Tạo AVD không cần Java (`config.ini`), tạo simulator bằng `simctl`
- [x] Sửa AVD (RAM/storage/camera/orientation/keyboard/SD), giữ nguyên key lạ
- [x] Tuỳ chọn khởi chạy theo máy: headless, cold boot, camera, restart; lưu bền
- [x] Stream Android (scrcpy + input) và iOS simulator (SimulatorKit + HID)
- [x] Chrome thật DeviceKit cho iOS (bezel, mask, nút cạnh)
- [x] Screenshot, quay màn hình (REC clock), xoá/wipe an toàn
- [x] SDK Manager: image đã cài, tải về, licence, chặn xoá image đang dùng
- [x] MCP server loopback (14 tool)
- [x] Layout grid + spotlight dọc/ngang, kéo-thả đổi thứ tự tile
- [x] Toast cho start/stop/stream/capture/SDK, có cả trên sheet
- [x] **SD-009** Notification Center: panel thông báo ở góc dưới phải cửa sổ, các mục
      xếp chồng từ trên xuống (mới nhất sát góc; tự ẩn sau 6 s, tối đa 5, có nút đóng);
      chuông trên top bar + badge chưa đọc, popover 50 thông báo gần nhất, bấm dòng để
      hiện lại, Clear; lịch sử chỉ trong phiên
- [x] **SD-015** Settings UI (gear + ⌘,): headless mặc định, thư mục recording (chọn
      bằng NSOpenPanel, mặc định `~/Pictures/SimDeck`), layout mặc định, khung thiết bị
      mặc định; lưu trong `~/Library/Application Support/SimDeck/settings.json`
- [x] Wi-Fi pairing: mDNS pairing/connect service, nhập tay IP:port + mã, `adb pair/connect`
- [x] Logcat viewer: lọc text/level, tạm dừng, xoá, copy (giới hạn 3000 dòng)
- [x] iOS thiết bị thật: devicectl list, CoreMediaIO stream (chỉ xem), screenshot từ frame
- [x] Agent: MCP `start_device` headless + `stream`/`cold_boot`, không mở cửa sổ emulator; CLI `bin/simdeck` + `AGENT.md`
- [x] Tự khởi động SimDeck: `bin/simdeck` auto-launch, stdio bridge `bin/simdeck-mcp` cho OpenCode (app mở on demand)
- [x] Dọn repo: xoá `app/`, `packages/`, `art/`, `.github/`, `scripts/`, `packaging/`, `build/`, docs Flutter cũ; thêm README/TASK gốc
- [x] Giao diện theo design system SimUtil (tokens, sidebar, top bar, panel)
- [x] Fix app crash khi adb server/pipe đóng: `ProcessRunner.readAll` thay `readDataToEndOfFile()`; đã test `adb kill-server` khi đang stream
- [x] Fix stream Android đứt lặp: double-close video fd (reader giữ quyền close), log `errno`/`serverAlive` khi recv lỗi, chặn reconnect vô hạn (chỉ reset sau ≥30 s live), bỏ status từ session cũ — commit `5cbd839`
- [x] Xác minh nguyên nhân adb server bị kill: build Gradle của `rangbox` (Godot Android) và `xiao-zhu/android` gọi `adb kill-server` sau mỗi build (5/5 mốc khớp trong ~1 s)
