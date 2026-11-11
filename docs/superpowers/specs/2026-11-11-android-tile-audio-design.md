# Tiếng trong tile cho Android — thiết kế

Ngày: 2026-11-11

## Vì sao

Tile SimDeck hiện chỉ có hình: scrcpy chạy `audio=false` và app không có
đường phát audio. Người dùng nghe tiếng nhờ chính tiến trình emulator phát
ra loa Mac, nên chỉ cần emulator bị bật với `-no-audio` (hoặc đổi thiết bị
ra) là im, trong khi guest vẫn chạy audio bình thường.

Mong muốn: nghe tiếng của thiết bị Android ngay trong tile, không phải
nghe đôi.

## Mục tiêu

- Android emulator do SimDeck khởi động: tiếng phát trong app, loa Mac im.
- Không vang đôi khi tile đang mở.
- Video vẫn chạy nếu audio lỗi (audio là best-effort).

## Không làm

- iOS simulator / iPhone: không đổi.
- Thu audio vào file recording của grid.
- UI volume/mute riêng, chọn thiết bị ra, đồng bộ A/V chính xác.
- Tiếng khi tile đóng hoặc khi `stream:false`.

## Ràng buộc đã kiểm tra

- scrcpy server bundled là 4.0, có audio; cần Android 11+ (emulator hiện
  tại là Android 16).
- Dùng `audio_codec=raw`: PCM 16-bit, 48 kHz, stereo, gói tối đa 4096
  byte; không cần decoder ngoài.
- Thứ tự socket khi `tunnel_forward=true`: video → audio → control. Dummy
  byte chỉ gửi trên socket đầu (video).
- Audio stream: 4 byte codec id (`0x00726177` = "raw"), sau đó mỗi gói là
  8 byte PTS/flags + 4 byte size + payload.
- Emulator đã chạy sẵn (không do SimDeck bật) không mute lại được.
- Điện thoại Android thật không mute được loa ngoài.

## Phương án

1. **scrcpy audio + emulator `-no-audio`** (đã chọn): một nguồn tiếng duy
   nhất, không vang đôi. Đổi lại tiếng chỉ có khi tile đang stream.
2. scrcpy audio, giữ loa host: ít sửa nhất nhưng nghe đôi/echo.
3. Không forward audio, chỉ cảnh báo emulator bị mute: tile vẫn im.

## Thiết kế

- `ScrcpySession`
  - Server args: bỏ `audio=false`, thêm `audio=true`,
    `audio_codec=raw`.
  - `connectAudio()` chèn giữa `connectVideo()` và `connectControl()`
    (đúng thứ tự accept của server).
  - Đọc 4 byte codec id; nếu là 0/1 (server tắt audio, ví dụ Android < 11)
    thì bỏ qua audio, video tiếp tục.
  - Mỗi gói raw đẩy sang `AudioSink`; `stop()` đóng socket audio và dừng
    sink.
- `AudioSink` (mới, `Sources/Streaming/AudioSink.swift`)
  - `AVAudioEngine` + `AVAudioPlayerNode`, format PCM 16-bit 48 kHz
    stereo interleaved.
  - Hàng đợi tối đa 8 buffer; vượt thì bỏ gói mới để giữ độ trễ thấp.
  - Engine chỉ start ở gói đầu; stop khi session dừng.
- `EmulatorController.start`: thêm `-no-audio` cho emulator Android do
  SimDeck bật (mọi trường hợp, kể cả cửa sổ emulator).
- Không đổi MCP, CLI, sidebar, Settings.

## Hệ quả / giới hạn

- Emulator do SimDeck bật sẽ im khi không có tile stream.
- Emulator đang chạy sẵn từ công cụ khác vẫn phát loa Mac; mở tile sẽ nghe
  đôi cho tới khi khởi động lại qua SimDeck.
- Điện thoại Android thật: tile có tiếng và loa điện thoại vẫn kêu (scrcpy
  không mute được thiết bị).
- Raw PCM tốn ~1,5 Mbit/s mỗi thiết bị trên adb nội bộ.

## Kiểm chứng

- Build Release.
- Bật một AVD qua SimDeck: `ps` của qemu có `-no-audio`; log app báo nhận
  gói audio; guest `dumpsys media.audio_flinger` vẫn ghi ra speaker.
- Hai emulator stream cùng lúc: cả hai có audio, không crash.
- Đóng tile / stop: engine dừng, không còn socket audio.
- Không có test tự động cho đường audio; kiểm chứng bằng chạy thật.
