# TASK

App SwiftUI trong `SimDeck/` **là toàn bộ app**; bản Flutter, `packages/` và các
workflow/script/packaging/docs cũ của nó đã bị xoá khỏi repo.

## Trạng thái hiện tại (2026-11-10)

- **Repo**: https://github.com/cuongdq88/simdeck — **PUBLIC**. Remote chỉ còn
  `master` và đó là default branch; commit mới nhất `9951c97`.
- **Release**: tag `simdeck-v1.0.0` (trỏ `5dcca85`), DMG
  `SimDeck-1.0.0-macos-arm64.dmg` — 4,534,797 bytes, SHA-256
  `11021a3d971a86c796279e9fd133584b472aa4aec2a5202a8fe32ffc67376885`,
  ad-hoc signed:
  https://github.com/cuongdq88/simdeck/releases/tag/simdeck-v1.0.0
- **App**: SwiftUI native trong `SimDeck/`, build Release OK, icon riêng
  (`Assets.xcassets` + `AppIcon.icns`), logo sidebar mới.
- **Agent**: MCP loopback `http://127.0.0.1:8765/mcp` (23 tool), CLI
  `SimDeck/bin/simdeck`, bridge stdio `SimDeck/bin/simdeck-mcp` (OpenCode dùng bridge,
  tự bật app). `start_device` luôn boot headless — không có cửa sổ emulator riêng.
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

- [ ] **SD-019 — MCP parity, phần còn lại (5 tool của bản cũ 27 tool)** sau SD-014:
      - `run_scenario` / `stop_scenario` — **chờ SD-010**
      - `set_slim` / `set_slim_mode`, `repair_input` — đặc thù iOS simulator; bản Swift
        không có slim mode nên nhiều khả năng bỏ, chưa chốt
- [ ] **SD-010 — Scenarios**: YAML (đúng format cũ), editor, runner chạy song song
      nhiều máy + panel bên phải hiện tiến trình; mở khoá `run_scenario`/`stop_scenario`
- [ ] **SD-016 — Agent mode không cửa sổ**: `SIMDECK_AGENT=1` (accessory, không WindowGroup) hoặc target CLI `simdeck-mcp` cho CI — hiện blocked vì SwiftUI `WindowGroup` luôn mở cửa sổ
- [ ] **SD-018 — iOS thật, tương tác**: hiện view-only; thêm input khi có thiết bị thật
      (blocked: chưa có máy)

## Đã xong

- [x] Tạo iOS simulator đúng runtime: runtime cài cho một loại máy (ví dụ
      `iOS-27-2-iPhone19-4` chỉ hỗ trợ "iPhone Duo") làm mọi máy khác fail
      `Incompatible device` (403). Giờ chọn runtime theo `supportedDeviceTypes`:
      sheet chỉ hiện runtime tương thích và tự đổi theo Device, MCP validate và báo rõ.
      Đã tạo được iPhone 17 Pro / Pro Max cả qua sheet lẫn MCP.

- [x] Boot chờ đúng cách khi mở stream: `adb shell` trả "adb: device offline" (hoặc
      treo) nếu emulator chưa lên hẳn, trước đây làm tile báo "The device did not
      finish booting". Giờ poll `getprop sys.boot_completed` 2 s/lần, thử lại tới
      300 s, chỉ báo lỗi kèm lý do cuối cùng
- [x] Tên thiết bị có dấu cách: `emulator` crash (SIGSEGV) khi `.ini`/thư mục AVD có
      dấu cách, nên tên người dùng nhập chỉ nằm trong `avd.ini.displayname`, còn file
      dùng `_` (`Space Test` → `Space_Test`); sidebar/MCP hiện tên có dấu cách và tra
      được theo cả tên lẫn id; iOS simulator nhận tên có dấu cách trực tiếp
- [x] Thiết bị: list/create/start/stop/wipe/delete, search, guards
- [x] Tạo AVD không cần Java (`config.ini`), tạo simulator bằng `simctl`
- [x] Sửa AVD (RAM/storage/camera/orientation/keyboard/SD), giữ nguyên key lạ
- [x] Tuỳ chọn khởi chạy theo máy: headless, cold boot, camera, restart; lưu bền
- [x] Stream Android (scrcpy + input) và iOS simulator (SimulatorKit + HID)
- [x] Chrome thật DeviceKit cho iOS (bezel, mask, nút cạnh)
- [x] Screenshot, quay màn hình (REC clock), xoá/wipe an toàn
- [x] SDK Manager: image đã cài, tải về, licence, chặn xoá image đang dùng
- [x] MCP server loopback (23 tool)
- [x] **SD-014** MCP tool parity: bản cũ 27 tool, bản Swift 23 tool — thêm
      `get_spotlight`, `connect_device`, `pair_device`, `disconnect_device`,
      `record_device`, `install_app`, `launch_app`, `find_elements`, `tap {label}`
      (đọc cây `uiautomator dump`, tap theo nhãn/id/value) và `record_grid`, cộng thêm
      `stop_device` mà bản cũ không có. `find_elements`/`tap {label}` chỉ chạy trên
      Android; iOS simulator trả lỗi rõ. 5 tool còn thiếu theo dõi ở **SD-019**
- [x] **Release 1.0.0** (2026-11-09): build Release từ `5dcca85`, DMG `UDZO` có app +
      link Applications + `LICENSE` + `third_party/`, `hdiutil verify` VALID, mount thử
      OK; tag + GitHub Release `simdeck-v1.0.0` kèm asset DMG. GitHub sau đó đổi
      `main` → `master` (default branch) và docs trỏ theo `master`.
- [x] **SD-012** Grid recording: quay toàn bộ cửa sổ SimDeck bằng ScreenCaptureKit ra
      H.264 MP4, 4 mức chất lượng low/standard/high/smooth (15/24/30/60 fps,
      720p/1280 px/full size) chọn trong Settings và lưu vào `settings.json`; top bar
      có REC + đồng hồ và nút dừng; cửa sổ Recordings liệt kê file trong thư mục capture
      (mở / Reveal in Finder / xoá). Chỉ một recording (lưới hoặc thiết bị) chạy một lúc
- [x] Layout grid + spotlight dọc/ngang, kéo-thả đổi thứ tự tile
- [x] Thông báo in-app (panel góc dưới phải) cho start/stop/stream/capture/SDK, có cả trên sheet
- [x] **SD-009** Notification Center: panel thông báo ở góc dưới phải cửa sổ, các mục
      xếp chồng từ trên xuống, mới nhất ở trên, trượt vào từ mép phải (tự ẩn sau 6 s,
      tối đa 5, có nút đóng); chuông trên top bar + badge chưa đọc, popover 50 thông
      báo gần nhất, bấm dòng để hiện lại, Clear; lịch sử chỉ trong phiên
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
