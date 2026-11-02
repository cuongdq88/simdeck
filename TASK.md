# TASK

Việc còn lại của app SwiftUI trong `SimDeck/` (bản Flutter `app/` + `packages/` vẫn giữ
nguyên, chưa thay thế).

## Hoãn — làm sau

- [ ] **Notification Center trong app**: lịch sử thông báo (toast gần đây) trong một
      panel/popover, bấm để mở lại; hiện chỉ có toast thoáng qua.

## Đang làm

- [ ] **Logcat viewer** cho thiết bị Android (adb logcat, lọc theo tag/level, tạm dừng)

## Tiếp theo

- [ ] **Scenarios**: YAML, editor, runner + panel bên phải
- [ ] **Plugin registry** (`~/.simutil/settings.yaml`) + chạy lệnh ngoài
- [ ] **iOS thiết bị thật**: liệt kê qua usbmux/devicectl, stream CoreMediaIO, chỉ xem
- [ ] **Grid recording**: ScreenCaptureKit + chọn chất lượng + danh sách recording đã lưu
- [ ] **Emulator gRPC video** (tuỳ chọn; scrcpy hiện đã phủ, chạy cả headless)
- [ ] **MCP tool parity**: bổ sung các tool còn thiếu của bản Flutter (27 tool)
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
- [x] Giao diện theo design system SimUtil (tokens, sidebar, top bar, panel)
