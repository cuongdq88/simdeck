# SimDeck — Trình quản lý máy ảo Android + iOS không cần Android Studio

Ngày: 2026-10-27
Trạng thái: chờ duyệt
Tên tạm: **SimDeck** (đổi được, không ảnh hưởng thiết kế)

## 1. Mục tiêu và lý do

Máy đã có Android SDK, emulator, `avdmanager`, Xcode — nhưng mọi thao tác quản lý AVD
vẫn phải mở Android Studio. Google không có app GUI độc lập cho AVD Manager.

Hai dự án mã nguồn mở (đều MIT) chia nhau đúng hai nửa của vấn đề:

- **SimUtil** (`dungngminh/simutil`, Flutter/Dart): GUI, stream nhiều máy bằng scrcpy,
  tap/gõ phím, record, quản lý iOS simulator, MCP server. **Không tạo được thiết bị.**
- **emu** (`wasabeef/emu`, Rust/TUI): tạo AVD, cài/xoá system image, wipe, delete,
  tạo iOS simulator. **Không có GUI, không stream.**

Mục tiêu: **một app duy nhất** làm được cả hai — tạo, cấu hình, chạy, xem, xoá thiết bị
ảo Android và iOS — không phụ thuộc Android Studio.

## 2. Goals

1. Tạo **và sửa** AVD Android từ GUI: hardware profile, API level, tag (Play/Google APIs), ABI,
   RAM, dung lượng, bàn phím, camera, hướng — dùng chung một form, tương đương tab "New/Edit Device"
   của Studio.
1b. Sửa AVD đã tạo chỉ khi máy đang tắt; ghi `config.ini` theo kiểu atomic (ghi file tạm rồi đổi tên),
   giữ nguyên các key không nằm trong form.
2. Tạo iOS simulator từ GUI qua `simctl`.
3. Quản lý runtime: xem system image / iOS runtime đã cài và có thể tải, cài, xoá, kèm tiến trình.
4. Start / stop / wipe / delete / reveal cho cả hai nền tảng.
5. Xem và điều khiển màn hình thiết bị đang chạy (Android qua scrcpy, iOS qua stream sẵn có của SimUtil).
6. Chẩn đoán môi trường: `ANDROID_HOME`, tool versions, license, Xcode, dung lượng trống.

## 3. Non-goals (v1)

- Không nhúng màn hình emulator kiểu Studio. Stream qua scrcpy đã tốt hơn và đã có sẵn.
- Không quản lý snapshot, không duplicate AVD, không nhóm AVD theo folder.
- Không sửa toàn bộ ~60 key của `config.ini`; v1 chỉ các key ở mục 2 (dùng chung cho Create và Edit),
  mọi key khác giữ nguyên từng byte.
- Không tải iOS runtime trong app; chỉ liệt kê, chọn khi tạo máy, và xoá bản đã cài. Tải runtime
  vẫn qua Xcode Settings.
- Không build cho Windows/Linux (chỉ macOS; hai dự án gốc vẫn hỗ trợ, nhưng ta không test được).
- Không auto-update: bản cài bằng brew thì `brew upgrade` là đường duy nhất, self-updater của
  SimUtil phải bị tắt (xem §12.2).
- Notarize chỉ khi có Apple Developer ID; nếu không, ký ad-hoc và ghi rõ cách bỏ quarantine (§12.3).
- Không đụng vào MCP server của SimUtil.

## 4. Anti-goals

- **Không** đọc trạng thái AVD chỉ từ một nguồn. Máy này đã chứng minh ba nguồn lệch nhau:
  `android emulator list` → E3,E2,E1; `emulator -list-avds` → E1,E2; `avdmanager list avd` → E1,E2.
  App hiển thị sai danh sách là thất bại, kể cả khi mọi nút đều bấm được.
- **Không** xoá nhầm thư mục dùng chung. Đã có tiền lệ: `E1.ini` và `Pixel_9_Pro_XL.ini`
  cùng trỏ `Pixel_9_Pro_XL.avd`; xoá một tên làm mất cả hai.
- Không được làm hỏng AVD đang có (`E2` / `OpenBookReview.avd`) trong bất kỳ thao tác nào.

## 5. Ràng buộc

- macOS Apple Silicon. Xcode 27.1 đã có. Flutter **chưa cài** (cần ≥ 3.38 / Dart ^3.11).
- Rust **chưa cài** cargo (chỉ cần để build helper, không cần cho người dùng cuối).
- `sdkmanager` đã bị Google deprecate ở cmdline-tools 23 nhưng vẫn chạy; `emu` phụ thuộc nó.
- App không sandbox (cần `adb`, USB, quyền chạy emulator) — giống SimUtil.
- Hai repo gốc đều MIT: phải giữ file LICENSE và ghi công trong About.

## 6. Các cách đã cân nhắc

| | Cách | Đánh giá |
|---|---|---|
| A | Fork SimUtil, **port** logic tạo AVD của emu sang Dart (~1.000 dòng) | Một ngôn ngữ, một binary. Nhưng port tay phần dễ sai nhất (license, parse `sdkmanager`, fallback skin) và bỏ lại 720 test |
| **B** | Fork SimUtil, **thêm CLI JSON vào emu**, nhúng emu làm helper | Logic đã test giữ nguyên; patch Rust nhỏ (~200 dòng); vẫn gửi PR upstream được. Đổi lại: đóng gói 2 binary |
| C | Viết mới bằng SwiftUI, mượn `SimStream.swift` của SimUtil | Native, không Flutter. Nhưng ~2.500 dòng mới, làm lại list/launch/wipe/stream cho 2 nền tảng |

**Chọn B.** Lý do: rủi ro lớn nhất của dự án nằm ở logic thiết bị, không ở UI. emu đã có
`AndroidManager`/`IosManager` tách khỏi UI và 720 test. Patch 200 dòng Rust rẻ hơn nhiều so
với port 1.000 dòng Dart, và giữ được khả năng merge từ upstream.

Đây là quyết định của người viết design, người duyệt có thể bác bỏ.

## 7. Kiến trúc

```
SimDeck.app  (fork SimUtil, Flutter/Dart)
├── phần có sẵn: device list, scrcpy stream, tap/type, record, iOS stream, MCP
├── mới: CreateDeviceSheet, RuntimeManager, EnvironmentCheck
├── mới: app/lib/src/bridge/  (Dart, gọi subprocess + guard an toàn)
└── Contents/Resources/emu          (helper Rust, universal, ký riêng)
```

- Base: fork `dungngminh/simutil` tại tag `app-v0.5.0`.
- Helper: fork `wasabeef/emu` tại `v1.3.0`, **giữ nguyên TUI**, chỉ thêm subcommand `--json`.
- Không sửa package `simutil_adb` của upstream trừ khi buộc phải; code mới nằm ở package riêng
  để merge upstream rẻ.

## 8. Hợp đồng giữa app và helper

Một dạng envelope duy nhất, dùng cho mọi lệnh:

```json
{ "ok": true,  "data": { }, "error": null }
{ "ok": false, "data": null, "error": { "code": "image_missing", "message": "...", "hint": "..." } }
```

Exit code: `0` thành công, `1` lỗi nghiệp vụ, `2` lỗi môi trường.

Lệnh v1:

```
emu --json env check
emu --json avd profiles                     # hardware profile: id, tên, kích thước màn hình
emu --json avd tags --api <N>               # tag + ABI có image đã cài
emu --json avd create --name --api --tag --abi --device --ram --storage [--camera] [--orientation] [--keyboard]
emu --json avd show   --name                  # config.ini đã parse, cho form Edit
emu --json avd update --name [--ram] [--storage] [--camera] [--orientation] [--keyboard] [--sdcard]
```
emu --json ios device-types                 # id + tên
emu --json ios runtimes                     # runtime đã cài
emu --json ios create --device-type <id> --runtime <id> --name
emu --json images list [--platform android|ios]
emu --json images install   --package <id>  # phát NDJSON tiến trình
emu --json images uninstall --package <id>
emu --json licenses status
emu --json licenses accept                  # phát NDJSON, chạy `sdkmanager --licenses`
```

Danh mục (profile, tag, ABI, iOS device type) do **helper** trả về, không để Dart tự gọi và
parse `avdmanager`/`simctl` — đó chính là phần logic ta chọn dùng lại từ emu.

**Phân chia trách nhiệm (quyết định của người viết design):** các thao tác phá huỷ
(`list`, `wipe`, `delete`) do **lớp Dart** của app thực hiện, vì nó phải chạy qua bộ kiểm tra
thư mục chia sẻ ở §10. Helper **không** phơi ra `avd delete`/`avd wipe` ở v1: bản của emu
hardcode `~/.android/avd` (bỏ qua `ANDROID_AVD_HOME`) và tự stop máy đang chạy — trái với §10.
Hệ quả: phải thay đường wipe/delete hiện có của SimUtil bằng bản trong `simdeck_bridge`,
và mọi entry point khác (CLI, MCP) cũng đi qua đó.

Tiến trình cài đặt: helper in NDJSON từng dòng `{"event":"progress","percent":42,"message":"..."}`
ra stdout; app đọc theo dòng. Lỗi giữa luồng vẫn theo envelope ở dòng cuối.

Ánh xạ lỗi tối thiểu: `license_required`, `image_missing`, `name_exists`, `device_not_found`,
`disk_full`, `sdk_not_found`, `tool_failed`.

## 9. Màn hình

1. **Sidebar** (sửa từ SimUtil): tab `Android` / `iOS`; nhóm `Running` / `Stopped`; ô tìm kiếm.
   Menu chuột phải: Start, Stop, Wipe, Delete, Reveal in Finder, Details.
2. **Create / Edit Device** (mới): segmented Android/iOS → form chung.
   Android: tên (tự sinh từ profile + API), profile (danh sách có kích thước màn hình),
   API (chỉ hiện image đã cài; image chưa cài hiện kèm nút Download), tag, ABI, RAM, storage,
   Play toggle, Advanced (camera, orientation, sdcard, keyboard). Footer: dung lượng cần + Create.
   iOS: device type, runtime, tên.
   **Chế độ Edit** (Android): chỉ mở RAM, storage, camera, orientation, keyboard, sdcard.
   Profile, API, tag, ABI và Play bị khoá — đổi chúng là tạo AVD mới, giống Studio.
3. **Runtime Manager** (mới): bảng đã cài / có thể tải, size, nút Install/Uninstall, thanh tiến trình,
   prompt chấp nhận license.
4. **Details** (mở rộng): các key `config.ini` đang dùng, path, dung lượng chiếm, trạng thái,
   nút **Edit** (mờ khi máy đang chạy).
5. **Environment** (mới): `ANDROID_HOME`, phiên bản `adb`/`emulator`/`avdmanager`, có Xcode,
   license đã chấp nhận chưa, dung lượng trống. Copy được để dán khi báo lỗi.

## 10. Nguồn sự thật và an toàn dữ liệu

- Danh sách AVD: đọc trực tiếp `$ANDROID_AVD_HOME` (hoặc `~/.android/avd`) gồm `*.ini` + `config.ini`
  là nguồn chính. `adb devices` chỉ để biết máy nào đang chạy. `emulator -list-avds` chỉ dùng
  để đối chiếu và hiện cảnh báo khi lệch.
- Trước mọi thao tác phá huỷ (wipe/delete): resolve thư mục từ `.ini`; nếu **bất kỳ `.ini` khác**
  trỏ cùng thư mục → chặn, hiện tên các entry chia sẻ. Đây là bẫy E1/Pixel_9_Pro_XL.
- Thiết bị đang chạy: wipe/delete bị chặn cho tới khi stop; delete luôn hỏi xác nhận, wipe yêu cầu gõ tên.
- Trước khi tạo: kiểm tra dung lượng trống ≥ size image + 8 GB.
- Nếu Android Studio đang chạy: cảnh báo có thể tranh chấp `config.ini` khi sửa.
- Không bao giờ ghi vào AVD đang chạy.
- Xoá system image đang được AVD dùng → **chặn**, liệt kê AVD đang dùng. Không có ngoại lệ ghi đè.
- Mọi thao tác phá huỷ của SimUtil (kể cả qua CLI và MCP) phải đi qua bộ kiểm tra này; nếu không,
  guard chỉ là trang trí.

## 11. Kiểm thử và tiêu chí nghiệm thu

Kiểm thử tự động:
- Rust: `cargo test` của emu phải xanh; thêm test cho từng subcommand `--json` (envelope, exit code).
- Dart: parse envelope, map lỗi, validate tên, resolve thư mục, phát hiện thư mục chia sẻ.

Nghiệm thu thủ công, trên AVD nháp `ZZ_Test` và simulator `ZZ_Test`:

1. Tạo AVD `ZZ_Test` API 36 Play arm64 → `android emulator list` thấy nó, `config.ini` có đúng RAM/storage đã chọn.
2. Start từ app → máy lên, stream hiện trong sidebar, tap/gõ hoạt động.
2b. Sửa `ZZ_Test` khi đang tắt: RAM 2048 → 4096. `diff config.ini` chỉ đổi đúng key `hw.ramSize`;
   các key khác y nguyên từng byte. Boot lại, `adb shell cat /proc/meminfo` phản ánh RAM mới.
   Thử sửa khi máy đang chạy → nút Edit mờ, gọi thẳng helper trả `device_running`.
3. Stop → biến mất khỏi nhóm Running, `adb devices` không còn.
4. Wipe → dữ liệu người dùng về mặc định, app vẫn boot.
5. Delete → thư mục + `.ini` biến mất, danh sách sạch.
6. Tạo simulator iOS → `xcrun simctl list` thấy; start/stop từ app.
7. Cài một system image chưa có → tiến trình chạy, kết thúc thì xuất hiện trong danh sách API.
8. Tạo lại bẫy chia sẻ: copy `ZZ_Test.ini` thành `ZZ_Test2.ini` cùng path → nút Delete bị chặn,
   thông báo nêu cả hai tên.
9. `E2` (OpenBookReview.avd): checksum `config.ini` trước và sau toàn bộ phiên test phải giống nhau.
10. App chạy được khi Android Studio đã xoá khỏi `/Applications` (hoặc không mở).

## 12. Đóng gói và phân phối

### 12.1 Người dùng cài bằng một lệnh

```bash
brew install --cask cuong/simdeck/simdeck
```

Tap riêng: repo `cuong/homebrew-simdeck`, một file `Casks/simdeck.rb`:

```ruby
cask "simdeck" do
  version "0.1.0"
  sha256 "<sha256 của dmg>"

  url "https://github.com/cuong/simdeck/releases/download/v#{version}/SimDeck-#{version}.dmg"
  name "SimDeck"
  desc "Virtual device manager for Android emulators and iOS simulators"
  homepage "https://github.com/cuong/simdeck"

  depends_on macos: ">= :monterey"
  depends_on formula: "ffmpeg"          # chỉ cần cho record
  depends_on cask: "android-platform-tools"   # adb; emulator/avdmanager vẫn phải có Android SDK

  app "SimDeck.app"

  caveats <<~EOS
    SimDeck cần Android SDK (emulator, avdmanager) và Xcode cho iOS.
    Nếu macOS báo "SimDeck is damaged", chạy:
      xattr -dr com.apple.quarantine "/Applications/SimDeck.app"
  EOS
end
```

Cask chứ không phải Formula: sản phẩm là `.app` có GUI, đó đúng loại artifact cask quản lý.
`brew upgrade --cask simdeck` là đường cập nhật duy nhất.

### 12.2 Phải tắt self-update của SimUtil

SimUtil tự cập nhật "in place từ nơi đã cài". Với bản do brew quản lý, việc này **phá** cask:
brew nghĩ version A, app tự thành version B, sha256 lệch. Phải tắt hẳn self-updater khi build
fork (xoá đường update, hoặc trả `null` cho update controller).

### 12.3 Gatekeeper — chỗ dễ hỏng nhất

Hai lựa chọn, phải chọn trước khi release:

| | Có Apple Developer ID ($99/năm) | Không có |
|---|---|---|
| Ký | Developer ID + hardened runtime | ad-hoc (`codesign -s -`) |
| Notarize | `notarytool submit` + `stapler` | không |
| Trải nghiệm user | cài xong mở được ngay | macOS có thể báo "damaged"; phải `xattr -dr` hoặc `--no-quarantine` |
| Ghi chú | cần trong cask | phải nằm trong `caveats` + README |

Ký **helper trước, app sau**: `codesign` từ trong ra ngoài, nếu không Gatekeeper từ chối cả bundle.
Cả `emu` helper lẫn scrcpy server đều là binary lồng trong `Contents/Resources`, đều phải ký.

### 12.4 Build ra dmg

```
scripts/release.sh <version>
  1. cargo build --release --target aarch64-apple-darwin / x86_64-apple-darwin  (helper)
  2. lipo -create ... -output build/emu-universal
  3. codesign helper (hardened runtime)
  4. flutter build macos --release        (universal theo mặc định)
  5. copy helper vào SimDeck.app/Contents/Resources/, codesign app
  6. hdiutil / create-dmg → SimDeck-<version>.dmg
  7. shasum -a 256 → in ra để dán vào cask
  8. cập nhật Casks/simdeck.rb trong tap, commit "simdeck <version>"
```

Bước 1–7 chạy được trên máy; bước 8 làm tay lúc đầu, sau đó đưa vào GitHub Actions
(matrix không cần — chỉ macOS runner là đủ).

### 12.5 Release checklist

1. `flutter test`, `cargo test`, `flutter analyze` xanh.
2. Chạy 10 tiêu chí nghiệm thu ở §11 trên máy sạch (không có bản dev trong `/Applications`).
3. Build dmg, cài bằng `brew install --cask ./SimDeck-x.y.z.dmg` để thử đúng đường user đi.
4. Mở app từ `/Applications`, xác nhận không self-update, `brew upgrade` không phá app.
5. `brew uninstall --cask simdeck` → app biến mất, không để lại rác ngoài `~/.simutil`.


## 13. Rủi ro

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| Phải cài Flutter SDK (~1.5 GB) + build lần đầu lâu | chậm khởi động dự án | cài trước, chạy `flutter doctor` sớm |
| `sdkmanager` bị bỏ | Runtime Manager hỏng trong tương lai | tách lớp gọi, sau này thay bằng `android sdk` |
| Hai fork phải theo dõi upstream | merge đau | giữ code mới trong package riêng, patch `emu` nhỏ và tách biệt |
| emu là dự án non (83 sao, 1 tác giả) | bảo trì | logic nằm sau envelope JSON; thay bằng script khác được |
| `simctl create` cần runtime đã tải | UX tạo iOS thất bại | Runtime Manager chỉ rõ runtime nào thiếu |
| Không có Developer ID → Gatekeeper chặn | user thấy "damaged", mất niềm tin | notarize nếu có tài khoản; nếu không thì `caveats` + README nêu rõ `xattr -dr` |
| Self-update của SimUtil đá vào bản brew | sha256 lệch, `brew upgrade` hỏng | tắt self-updater, coi là điều kiện release (§12.2) |

## 14. Việc để builder tự quyết

- Đặt tên package Dart, schema field name chính xác.
- Cách hiển thị tiến trình (progress bar vs log cuộn).
- Có dùng thumbnail thiết bị hay chỉ chữ.
- Giữ nguyên TUI của `emu` trong binary hay build feature-gated.
