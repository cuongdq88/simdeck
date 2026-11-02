# TASK

App SwiftUI trong `SimDeck/` **là toàn bộ app**; bản Flutter, `packages/` và các
workflow/script/packaging/docs cũ của nó đã bị xoá khỏi repo.

## Hoãn — làm sau

- [ ] **Notification Center trong app**: lịch sử thông báo (toast gần đây) trong một
      panel/popover, bấm để mở lại; hiện chỉ có toast thoáng qua.

## Tiếp theo

- [ ] **Scenarios**: YAML, editor, runner + panel bên phải
- [ ] **Plugin registry** (`~/.simutil/settings.yaml`) + chạy lệnh ngoài
- [ ] **Grid recording**: ScreenCaptureKit + chọn chất lượng + danh sách recording đã lưu
- [ ] **Emulator gRPC video** (tuỳ chọn; scrcpy hiện đã phủ, chạy cả headless)
- [ ] **MCP tool parity**: bổ sung các tool còn thiếu của bản Flutter (27 tool)
- [ ] **Agent mode không cửa sổ**: `SIMDECK_AGENT=1` (accessory, không WindowGroup) hoặc target CLI `simdeck-mcp` cho CI
- [ ] **Settings UI**: headless mặc định, thư mục recording, thứ tự/khung mặc định

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
- [x] Wi-Fi pairing: mDNS pairing/connect service, nhập tay IP:port + mã, `adb pair/connect`
- [x] Logcat viewer: lọc text/level, tạm dừng, xoá, copy (giới hạn 3000 dòng)
- [x] iOS thiết bị thật: devicectl list, CoreMediaIO stream (chỉ xem), screenshot từ frame
- [x] Agent: MCP `start_device` headless + `stream`/`cold_boot`, không mở cửa sổ emulator; CLI `bin/simdeck` + `AGENT.md`
- [x] Tự khởi động SimDeck: `bin/simdeck` auto-launch, stdio bridge `bin/simdeck-mcp` cho OpenCode (app mở on demand)
- [x] Dọn repo: xoá `app/`, `packages/`, `art/`, `.github/`, `scripts/`, `packaging/`, `build/`, docs Flutter cũ; thêm README/TASK gốc
- [x] Giao diện theo design system SimUtil (tokens, sidebar, top bar, panel)
