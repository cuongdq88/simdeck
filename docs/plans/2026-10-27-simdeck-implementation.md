# SimDeck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Một app macOS cài bằng brew quản lý trọn vòng đời máy ảo Android và iOS simulator — tạo, sửa, cài runtime, chạy, xem, xoá — không cần Android Studio.

**Architecture:** Fork SimUtil (Flutter) làm thân app; fork emu (Rust) và bổ sung CLI JSON, nhúng làm helper trong `.app`. Mọi thao tác phá huỷ đi qua lớp guard bằng Dart; mọi thao tác tạo/cài đi qua helper.

**Tech Stack:** Flutter ≥ 3.38 / Dart ^3.11; Rust (cargo, clap, serde, tokio) từ emu 1.3.0; `avdmanager`, `sdkmanager`, `emulator`, `adb`, `xcrun simctl`.

**Spec:** `docs/specs/2026-10-27-simdeck-design.md`

**Deviation ghi nhận:** bridge nằm trong `app/lib/src/bridge/` thay vì package riêng — một package mới không mua được gì trong fork này.

## Global Constraints

- Chỉ macOS; Apple Silicon là nơi test. Không build Windows/Linux.
- `flutter analyze` không được có warning mới; `cargo test` của emu phải xanh.
- Envelope JSON duy nhất: `{"ok":bool,"data":object|null,"error":{"code","message","hint"}|null}`; exit 0/1/2.
- Không sửa `packages/simutil_adb` trừ khi task ghi rõ; code mới nằm ở `app/lib/src/bridge/` và UI.
- `config.ini`: chỉ ghi các key trong form Edit; mọi key khác giữ nguyên từng byte; ghi atomic (file tạm + rename).
- Không bao giờ wipe/delete thiết bị đang chạy; không xoá AVD có thư mục dùng chung; không xoá system image đang được dùng.
- Không tự cập nhật: `AppUpdateCubit` phải bị vô hiệu hoá trong bản build phát hành.
- Giữ `LICENSE` của simutil và emu; ghi công trong About.
- Mọi message hướng tới người dùng bằng tiếng Anh; comment code bằng tiếng Anh.

## Review Focus

1. Hai `.ini` trỏ cùng thư mục AVD → delete phải bị chặn và nêu cả hai tên (Task 10).
2. Xoá system image đang được AVD dùng → chặn, liệt kê AVD (Task 10).
3. Wipe/delete khi máy đang chạy → chặn, không tự stop (Task 10).
4. Edit ghi `config.ini` làm mất key lạ/comment → test round-trip so byte (Task 5).
5. License SDK chưa chấp nhận giữa lúc install → app báo được, không treo (Task 6, Task 12).
6. Tên AVD có dấu cách, dấu chấm, ký tự Unicode → validate trước khi gọi `avdmanager` (Task 4).
7. Ổ đĩa không đủ chỗ → từ chối trước khi tải image (Task 4, Task 12).

---

### Task 1: Baseline — fork SimUtil, toolchain, build xanh

**Files:**
- Create: `/Users/cuong/Workspace/Projects/SimDeck.Project/` (repo, fork), `~/Workspace/emu/` (fork)
- Modify: `/Users/cuong/Workspace/Projects/SimDeck.Project/.git/config` (remotes)

**Interfaces:**
- Produces: `flutter` 3.47.x trong PATH; `cargo` trong PATH; hai repo có remote `upstream`.

- [ ] **Step 1: Cài toolchain còn thiếu**

```bash
brew install --cask flutter
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
flutter --version   # phải >= 3.38.0, Dart ^3.11
cargo --version
```

- [ ] **Step 2: Clone hai bản fork tại tag đã chốt**

```bash
git clone https://github.com/dungngminh/simutil /Users/cuong/Workspace/Projects/SimDeck.Project
cd /Users/cuong/Workspace/Projects/SimDeck.Project && git remote rename origin upstream && git checkout app-v0.5.0
git clone https://github.com/wasabeef/emu ~/Workspace/emu
cd ~/Workspace/emu && git remote rename origin upstream && git checkout v1.3.0
```

- [ ] **Step 3: Xác nhận baseline xanh trước khi sửa**

```bash
cd ~/Workspace/emu && cargo test
cd /Users/cuong/Workspace/Projects/SimDeck.Project && flutter pub get && flutter test && flutter analyze
```

Expected: `cargo test` và `flutter test` pass; `flutter analyze` sạch.

- [ ] **Step 4: Build thử bản macOS chưa sửa**

```bash
cd /Users/cuong/Workspace/Projects/SimDeck.Project/app && flutter build macos --release
ls build/macos/Build/Products/Release/SimUtil.app
```

- [ ] **Step 5: Commit**

```bash
cd /Users/cuong/Workspace/Projects/SimDeck.Project && git add -A && git commit -m "chore: fork simutil at app-v0.5.0"
cd ~/Workspace/emu && git add -A && git commit -m "chore: fork emu at v1.3.0"
```

---

### Task 2: Helper — khung CLI JSON + `env check`

**Files:**
- Create: `src/cli/mod.rs`, `src/cli/json.rs`, `src/cli/check.rs`
- Modify: `src/main.rs` (thêm subcommand, giữ nguyên đường TUI khi không có subcommand), `src/lib.rs`

**Interfaces:**
- Produces:
  - `pub struct Response<T> { pub ok: bool, pub data: Option<T>, pub error: Option<ErrBody> }`
  - `pub struct ErrBody { pub code: String, pub message: String, pub hint: Option<String> }`
  - `pub fn emit_ok<T: serde::Serialize>(data: T) -> std::process::ExitCode`
  - `pub fn emit_err(code: &str, message: &str, hint: Option<&str>) -> std::process::ExitCode`
  - `pub enum Cmd { Env(EnvCmd), Avd(AvdCmd), Images(ImagesCmd), Ios(IosCmd), Licenses(LicensesCmd) }`

- [ ] **Step 1: Viết test thất bại cho envelope**

`src/cli/json.rs` test module:

```rust
#[test]
fn error_envelope_has_code_message_hint() {
    let v = serde_json::to_value(err_value("image_missing", "no image", Some("run install"))).unwrap();
    assert_eq!(v["ok"], false);
    assert_eq!(v["data"], serde_json::Value::Null);
    assert_eq!(v["error"]["code"], "image_missing");
    assert_eq!(v["error"]["hint"], "run install");
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run: `cargo test cli::json::error_envelope -- --nocapture`
Expected: FAIL `cannot find function err_value`.

- [ ] **Step 3: Implement `src/cli/json.rs`**

`err_value` trả `serde_json::Value`; `emit_ok`/`emit_err` in một dòng JSON ra stdout và trả `ExitCode::from(0|1)`. `env check` trả `sdk_not_found` (exit 2) khi thiếu SDK.

- [ ] **Step 4: Nối vào `main.rs`**

Nếu `cmd` là `None` → chạy TUI như cũ. Có subcommand → không khởi tạo terminal, chỉ in JSON.

- [ ] **Step 5: Chạy test và thử tay**

```bash
cargo test && ./target/debug/emu --json env check | jq .
echo $?   # 0 khi ANDROID_HOME hợp lệ
```

Expected: JSON có `"ok": true`, `data.sdk_path`, `data.tools.adb`.

- [ ] **Step 6: Commit**

```bash
git add src/cli src/main.rs src/lib.rs && git commit -m "feat(cli): add json envelope and env check"
```

---

### Task 3: Helper — danh mục đọc (profile, tag, iOS device type, runtime, license)

**Files:**
- Create: `src/cli/catalog.rs`
- Modify: `src/cli/mod.rs`, `src/managers/android/discovery.rs` (chỉ thêm hàm `pub` nếu chưa có)

**Interfaces:**
- Consumes: `AndroidManager::list_available_devices()`, `list_available_system_images()`, `IosManager::list_device_types_with_names()`, `list_runtimes()`
- Produces JSON shapes (khoá chính xác):
  - `avd profiles` → `[{"id","name","width","height","density"}]`
  - `avd tags --api N` → `[{"tag","abi","installed":bool}]`
  - `ios device-types` → `[{"id","name"}]`
  - `ios runtimes` → `[{"id","name","version"}]`
  - `licenses status` → `{"accepted":bool,"missing":["android-sdk-license"]}`

- [ ] **Step 1: Viết test thất bại**

```rust
#[test]
fn profiles_are_sorted_and_have_dimensions() {
    let rows = parse_profiles(FIXTURE_DEVICE_LIST);
    assert!(rows.windows(2).all(|w| w[0].name <= w[1].name));
    assert_eq!(rows[0].width > 0, true);
}
```

- [ ] **Step 2: Chạy test** — Run: `cargo test cli::catalog::profiles -- --nocapture`; Expected FAIL.

- [ ] **Step 3: Implement `catalog.rs`** — đọc từ manager, map sang struct `#[derive(Serialize)]`, không parse lại text trong CLI.

- [ ] **Step 4: Test pass** — Run: `cargo test cli::catalog`; Expected PASS.

- [ ] **Step 5: Thử tay trên máy thật**

```bash
./target/debug/emu --json avd profiles | jq 'length'        # > 90
./target/debug/emu --json avd tags --api 36 | jq .
./target/debug/emu --json ios runtimes | jq .
```

- [ ] **Step 6: Commit** — `git commit -am "feat(cli): expose device profiles, tags, ios catalogs"`

---

### Task 4: Helper — `avd create`

**Files:**
- Create: `src/cli/create.rs`
- Modify: `src/managers/android/create.rs` (chỉ đổi visibility + trả `Result<PathBuf>` thay vì `()` nếu cần)
- Test: `src/cli/create.rs` test module

**Interfaces:**
- Consumes: `AndroidManager::create_device(config)`
- Produces: `avd create --name --api --tag --abi --device --ram --storage [--camera] [--orientation] [--keyboard]` → `{"name","path","config":{...}}`
- Validate (thứ tự, fail sớm): tên khớp `^[A-Za-z0-9._-]{1,64}$` → `invalid_name`; đã tồn tại → `name_exists`; image thiếu → `image_missing`; trống < image + 8 GB → `disk_full`.

- [ ] **Step 1: Viết test thất bại cho validate**

```rust
#[test]
fn rejects_names_with_spaces() {
    assert_eq!(validate_name("Pixel 9").unwrap_err().code, "invalid_name");
}

#[test]
fn rejects_existing_name() {
    assert_eq!(check_free_space(0, 10_000).unwrap_err().code, "disk_full");
}
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement validate + gọi manager** — sau khi `avdmanager` xong, set các key RAM/storage/camera/orientation/keyboard qua `fine_tune_avd_config` (đã có sẵn function), rồi trả path.

- [ ] **Step 4: Test pass** — Run: `cargo test cli::create`.

- [ ] **Step 5: Thử tay với AVD nháp**

```bash
./target/debug/emu --json avd create --name ZZ_Test --api 36 --tag google_apis_playstore \
  --abi arm64-v8a --device medium_phone --ram 2048 --storage 8G | jq .
android emulator list | grep ZZ_Test
grep -E "hw.ramSize|disk.dataPartition.size" ~/.android/avd/ZZ_Test.avd/config.ini
```

- [ ] **Step 6: Commit** — `git commit -am "feat(cli): add avd create with validation"`

---

### Task 5: Helper — `avd show` + `avd update` (ghi atomic, giữ key lạ)

**Files:**
- Create: `src/cli/config_ini.rs`
- Modify: `src/cli/mod.rs`
- Test: `src/cli/config_ini.rs` test module

**Interfaces:**
- Produces:
  - `avd show --name` → `{"name","path","config":{...},"editable":{"ram","storage","camera","orientation","keyboard","sdcard"}}`
  - `avd update --name [--ram][--storage][--camera][--orientation][--keyboard][--sdcard]` → `{"name","changed":["hw.ramSize"]}`
  - `pub fn apply_patch(original: &str, patch: &[(String, String)]) -> String`

- [ ] **Step 1: Viết test thất bại — bảo toàn byte**

```rust
#[test]
fn keeps_unknown_keys_and_comments() {
    let src = "# hand written\nAvdId=E2\nweird.key=1\nhw.ramSize=2048\n";
    let out = apply_patch(src, &[("hw.ramSize".into(), "4096".into())]);
    assert!(out.contains("# hand written"));
    assert!(out.contains("weird.key=1"));
    assert!(out.contains("hw.ramSize=4096"));
    assert_eq!(out.matches("hw.ramSize").count(), 1);
}
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement `apply_patch`** — sửa tại chỗ theo dòng, giữ thứ tự và comment; key mới append cuối. Ghi bằng `config.ini.tmp` + `rename`.

- [ ] **Step 4: Từ chối khi máy đang chạy** — kiểm tra qua `adb devices` / tiến trình qemu của AVD; trả `device_running`.

- [ ] **Step 5: Test pass** — Run: `cargo test cli::config_ini`.

- [ ] **Step 6: Thử tay round-trip**

```bash
cp ~/.android/avd/E2.avd/config.ini /tmp/e2.before
./target/debug/emu --json avd update --name ZZ_Test --ram 4096 | jq .
diff /tmp/e2.before ~/.android/avd/E2.avd/config.ini   # phải rỗng
```

- [ ] **Step 7: Commit** — `git commit -am "feat(cli): avd show/update with atomic in-place ini patch"`

---

### Task 6: Helper — `images list/install/uninstall`, `licenses accept`

**Files:**
- Create: `src/cli/images.rs`, `src/cli/progress.rs`
- Modify: `src/cli/mod.rs`
- Test: `src/cli/progress.rs` test module

**Interfaces:**
- Produces:
  - `images list [--platform android|ios]` → `[{"package","api","tag","abi","installed":bool,"size_bytes":int}]`
  - `images install --package <id>` → NDJSON: `{"event":"progress","percent":0..100,"message":str}` … dòng cuối `{"event":"done","ok":true,...}`
  - `images uninstall --package <id>` → `{"package","removed":true}`
  - `licenses accept` → NDJSON progress + `{"event":"done","accepted":true}`
  - `pub fn parse_sdkmanager_percent(line: &str) -> Option<u8>`

- [ ] **Step 1: Viết test thất bại**

```rust
#[test]
fn parses_progress_percent() {
    assert_eq!(parse_sdkmanager_percent("[=====    ] 45% Computing updates..."), Some(45));
    assert_eq!(parse_sdkmanager_percent("just a line"), None);
}
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement** — đọc stdout của `sdkmanager` theo dòng, mỗi dòng khớp `%` thì in NDJSON và `flush`; license prompt thì tự trả `y` khi chế độ `licenses accept`.

- [ ] **Step 4: Test pass** — Run: `cargo test cli::progress`.

- [ ] **Step 5: Thử tay (image nhỏ, đã cài thì bỏ qua)**

```bash
./target/debug/emu --json images list | jq 'length'
./target/debug/emu --json licenses status | jq .
```

- [ ] **Step 6: Commit** — `git commit -am "feat(cli): image install/uninstall with ndjson progress and license acceptance"`

---

### Task 7: Helper — `ios create`

**Files:**
- Create: `src/cli/ios.rs`
- Modify: `src/managers/ios/mod.rs` (thêm hàm `create_simulator` gọi `xcrun simctl create`)
- Test: `src/cli/ios.rs` test module

**Interfaces:**
- Produces: `ios create --device-type <id> --runtime <id> --name` → `{"udid","name"}`
- Lỗi: runtime chưa cài → `runtime_missing` (hint: Xcode Settings → Platforms), tên trùng → `name_exists`.

- [ ] **Step 1: Viết test thất bại**

```rust
#[test]
fn missing_runtime_is_reported_with_hint() {
    let e = map_create_error("Invalid runtime");
    assert_eq!(e.code, "runtime_missing");
    assert!(e.hint.unwrap().contains("Xcode"));
}
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement** — `simctl create <name> <device-type> <runtime>`, parse UDID từ stdout; map lỗi.

- [ ] **Step 4: Test pass + thử tay**

```bash
./target/debug/emu --json ios create --device-type "iPhone 17" --runtime "iOS 26" --name ZZ_Test | jq .
xcrun simctl list devices | grep ZZ_Test
```

- [ ] **Step 5: Commit** — `git commit -am "feat(cli): add ios simulator create"`

---

### Task 8: Build universal helper + script release

**Files:**
- Create: `scripts/build-helper.sh`, `scripts/release.sh`
- Test: chạy script, kiểm tra `lipo -info`

**Interfaces:**
- Produces: `build/emu-universal` (arm64 + x86_64), ký ad-hoc hardened runtime; `scripts/release.sh <version>` tạo `build/SimDeck-<version>.dmg` và in sha256.

- [ ] **Step 1: Viết `scripts/build-helper.sh`**

```bash
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create target/*/release/emu -output build/emu-universal
codesign -s - --options runtime --timestamp=none build/emu-universal
```

- [ ] **Step 2: Chạy và kiểm chứng**

```bash
bash scripts/build-helper.sh
lipo -info build/emu-universal     # phải nêu cả arm64 và x86_64
codesign -dv build/emu-universal 2>&1 | grep runtime
```

- [ ] **Step 3: Viết `scripts/release.sh`** — build helper → copy vào `SimDeck.app/Contents/Resources/emu` → `codesign` app → `hdiutil create -format UDZO` → `shasum -a 256`.

- [ ] **Step 4: Chạy thử** — `bash scripts/release.sh 0.1.0`; Expected: dmg tồn tại, sha256 in ra, `spctl -a -vv` báo bị từ chối (đúng, vì ad-hoc) — ghi nhận, không sửa.

- [ ] **Step 5: Commit** — `git add scripts && git commit -m "build: universal emu helper and dmg release script"`

---

### Task 9: Dart bridge — gọi helper, decode envelope, map lỗi

**Files:**
- Create: `app/lib/src/bridge/emu_bridge.dart`, `app/lib/src/bridge/emu_models.dart`, `app/lib/src/bridge/emu_exception.dart`
- Test: `app/test/bridge/emu_bridge_test.dart`

**Interfaces:**
- Produces:
  - `class EmuBridge { EmuBridge({required String emuPath, ProcessRunner? runner}); Future<T> run<T>(List<String> args, T Function(Object? json) parse); Stream<InstallProgress> install(String package); }`
  - `abstract class ProcessRunner { Future<ProcessResult> run(String exe, List<String> args); Stream<String> stream(String exe, List<String> args); }`
  - `class EmuException implements Exception { final String code; final String message; final String? hint; }`
  - `class AvdProfile`, `AvdTag`, `IosDeviceType`, `IosRuntime`, `AvdConfig`, `InstallProgress { int percent; String message; }`

- [ ] **Step 1: Viết test thất bại**

```dart
test('maps error envelope to EmuException', () async {
  final bridge = EmuBridge(emuPath: 'emu', runner: FakeRunner(
    result: ProcessResult(1, 1, '{"ok":false,"data":null,"error":{"code":"image_missing","message":"m","hint":"h"}}', '')));
  expect(() => bridge.run(['avd','create'], (j) => j),
      throwsA(isA<EmuException>().having((e) => e.code, 'code', 'image_missing')));
});

test('surfaces non-json stdout as tool_failed', () async {
  final bridge = EmuBridge(emuPath: 'emu', runner: FakeRunner(
    result: ProcessResult(2, 1, 'boom: not json', '')));
  expect(() => bridge.run(['env','check'], (j) => j), throwsA(isA<EmuException>()));
});
```

- [ ] **Step 2: Chạy test** — `cd app && flutter test test/bridge/emu_bridge_test.dart`; Expected FAIL.

- [ ] **Step 3: Implement** — decode dòng JSON cuối cùng của stdout; exit code 0 + `ok:true` → `parse(data)`; còn lại → `EmuException`; timeout 30 s cho lệnh thường.

- [ ] **Step 4: Test pass** — Run: `flutter test test/bridge/emu_bridge_test.dart`.

- [ ] **Step 5: Commit** — `git add app/lib/src/bridge app/test/bridge && git commit -m "feat(bridge): dart client for emu json cli"`

---

### Task 10: Guard an toàn + reroute wipe/delete

**Files:**
- Create: `app/lib/src/bridge/deletion_guard.dart`
- Modify: `app/lib/src/devices/devices_cubit.dart:228-250` (delete, wipeData)
- Modify: `app/lib/src/di.dart` (đăng ký `EmuBridge`, `DeletionGuard`)
- Test: `app/test/bridge/deletion_guard_test.dart`, `app/test/devices/delete_guard_test.dart`

**Interfaces:**
- Consumes: `EmuBridge.run`
- Produces:
  - `class IniFile { final String name; final String dirPath; }`
  - `class GuardVerdict { final bool allowed; final String? code; final String? message; }`
  - `class DeletionGuard { DeletionGuard({required Set<String> runningAvds, required List<IniFile> iniFiles}); factory DeletionGuard.fromFiles(List<IniFile> files); Future<GuardVerdict> checkAvd(String name); Future<GuardVerdict> checkImage(String package); }`
  - Mã: `shared_dir` (nêu cả hai `.ini`), `device_running`, `image_in_use`, `not_found`.

- [ ] **Step 1: Viết test thất bại — bẫy E1**

```dart
test('blocks delete when two ini share one avd dir', () async {
  final guard = DeletionGuard.fromFiles([
    IniFile('E1', '/Users/x/.android/avd/Pixel_9_Pro_XL.avd'),
    IniFile('Pixel_9_Pro_XL', '/Users/x/.android/avd/Pixel_9_Pro_XL.avd'),
  ]);
  final v = await guard.checkAvd('E1');
  assert(v.allowed, isFalse);
  assert(v.code, 'shared_dir');
  assert(v.message, contains('Pixel_9_Pro_XL'));
});

test('blocks when device is running', () async {
  final guard = DeletionGuard(runningAvds: {'ZZ_Test'}, iniFiles: [IniFile('ZZ_Test', '/p/ZZ_Test.avd')]);
  assert((await guard.checkAvd('ZZ_Test')).code, 'device_running');
});
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement guard** — đọc `$ANDROID_AVD_HOME` hoặc `~/.android/avd`; so sánh path đã `realpath`; running lấy từ `adb devices` + `adb emu avd name`; image đang dùng = quét `config.ini` của mọi AVD.

- [ ] **Step 4: Nối vào cubit** — `delete()`/`wipeData()` gọi `checkAvd` trước; bị chặn → phát `DeviceNoticeKind.error` với `v.message`, không gọi service.

- [ ] **Step 5: Test pass** — Run: `flutter test test/bridge/deletion_guard_test.dart test/devices/delete_guard_test.dart`.

- [ ] **Step 6: Kiểm chứng trên dữ liệu thật (không xoá)**

```bash
cp ~/.android/avd/E2.ini /tmp/dup.ini && sed -i '' 's/path.rel=.*/path.rel=avd\/OpenBookReview.avd/' /tmp/dup.ini
# trong app: nút Delete của E2 phải báo chặn; sau đó xoá /tmp/dup.ini nếu có tạo thử
```

- [ ] **Step 7: Commit** — `git commit -am "feat(guard): block shared-dir, running-device and in-use-image deletions"`

---

### Task 11: UI — Create / Edit Device

**Files:**
- Create: `app/lib/src/ui/create/create_device_sheet.dart`, `app/lib/src/ui/create/create_device_controller.dart`
- Modify: `app/lib/src/ui/devices/device_sidebar.dart` (nút + `c`), `app/lib/src/ui/shared/device_context_menu.dart` (menu Edit), `app/lib/src/app.dart` (route/sheet)
- Test: `app/test/create/create_device_controller_test.dart`

**Interfaces:**
- Consumes: `EmuBridge` (`avd profiles`, `avd tags`, `avd create`, `avd show`, `avd update`, `ios device-types`, `ios runtimes`, `ios create`)
- Produces: `CreateDeviceController` với `Future<void> loadCatalogs()`, `bool get canSubmit`, `Future<void> submit()`, `void setPlatform(Platform)`, và `CreateDeviceForm` state bất biến.

- [ ] **Step 1: Viết test thất bại — edit khoá field**

```dart
test('edit mode locks image fields but allows ram', () {
  final c = CreateDeviceController.forEdit(AvdConfig(ram: 2048, api: 36, tag: 'google_apis_playstore'));
  assert(c.editable.contains('ram'), isTrue);
  assert(c.editable.contains('tag'), isFalse);
});

test('cannot submit while a required field is empty', () {
  final c = CreateDeviceController.forCreate();
  assert(c.canSubmit, isFalse);
});
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement controller** — nạp catalog song song; tự sinh tên `"Pixel 9 API 36"`; chặn submit khi thiếu; lỗi bridge → hiện message + hint.

- [ ] **Step 4: Implement sheet** — segmented Android/iOS; form theo §9 của spec; footer hiện dung lượng cần; nút Create/Update.

- [ ] **Step 5: Test pass + chạy app thật**

```bash
cd app && flutter test test/create && flutter run -d macos
# tạo ZZ_UI (Android) và ZZ_iOS (iOS) qua UI, rồi kiểm tra bằng CLI
android emulator list | grep ZZ_UI
xcrun simctl list devices | grep ZZ_iOS
```

- [ ] **Step 6: Commit** — `git commit -am "feat(ui): create and edit device sheet"`

---

### Task 12: UI — Runtime Manager + Environment

**Files:**
- Create: `app/lib/src/ui/runtimes/runtime_manager_panel.dart`, `app/lib/src/ui/runtimes/runtime_manager_controller.dart`, `app/lib/src/ui/environment/environment_panel.dart`
- Modify: `app/lib/src/ui/top_bar.dart` (hai nút mở panel)
- Test: `app/test/runtimes/runtime_manager_controller_test.dart`

**Interfaces:**
- Consumes: `EmuBridge.install` (Stream), `images list/uninstall`, `licenses status/accept`, `env check`
- Produces: `RuntimeManagerController.install(package)` cập nhật `progress` 0..100 và trạng thái `licensesRequired`.

- [ ] **Step 1: Viết test thất bại**

```dart
test('license error flips licensesRequired instead of throwing', () async {
  final c = RuntimeManagerController(bridge: FakeBridge.licenseError());
  await c.install('system-images;android-35;google_apis;arm64-v8a');
  assert(c.licensesRequired, isTrue);
  assert(c.progress, 0);
});

test('progress reaches 100 then marks installed', () async {
  final c = RuntimeManagerController(bridge: FakeBridge.progress([0, 50, 100]));
  await c.install('pkg');
  assert(c.progress, 100);
  assert(c.installed.contains('pkg'), isTrue);
});
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement controller** — subscribe stream, cập nhật state, không ném lỗi ra UI.
  Trước khi gọi `images uninstall`, gọi `DeletionGuard.checkImage(package)`; bị chặn thì hiện
  danh sách AVD đang dùng thay vì gọi helper.

- [ ] **Step 4: Implement panel** — bảng đã cài/có thể tải; nút Accept licenses khi `licensesRequired`; cột dung lượng.

- [ ] **Step 5: Test pass + thử tay** — chọn một image chưa cài, bấm Install, thấy tiến trình chạy tới khi xong; danh sách API của form Create xuất hiện image đó.

- [ ] **Step 6: Commit** — `git commit -am "feat(ui): runtime manager and environment diagnostics"`

---

### Task 13: Đóng gói brew — tắt self-update, đổi tên, cask

**Files:**
- Modify: `app/lib/src/di.dart` (không đăng ký `AppUpdateCubit` khi `SIMDECK_NO_UPDATE=1`), `app/lib/src/ui/top_bar.dart` (ẩn nút update), `app/macos/Runner/Configs/AppInfo.xcconfig` (tên, bundle id `dev.cuong.simdeck`), `app/pubspec.yaml` (version `0.1.0`)
- Create: `packaging/Casks/simdeck.rb`, `packaging/README.md`
- Test: `app/test/update_disabled_test.dart`

**Interfaces:**
- Produces: app tên `SimDeck`, bundle `dev.cuong.simdeck`; cask `simdeck` version 0.1.0.

- [ ] **Step 1: Viết test thất bại — update bị tắt**

```dart
test('update cubit is not created when updates are disabled', () {
  final di = buildDi(env: {'SIMDECK_NO_UPDATE': '1'});
  expect(di.isRegistered<AppUpdateCubit>(), isFalse);
});
```

- [ ] **Step 2: Chạy test** — Expected FAIL.

- [ ] **Step 3: Implement** — nếu `di.dart` chưa có `buildDi`, tách phần đăng ký thành
  `GetIt buildDi({Map<String, String> env = const {}})`; release script export `SIMDECK_NO_UPDATE=1`;
  ẩn `update_toast` và nút update.

- [ ] **Step 4: Đổi tên bundle** — sửa `AppInfo.xcconfig` (`PRODUCT_NAME=SimDeck`, `PRODUCT_BUNDLE_IDENTIFIER=dev.cuong.simdeck`), build lại, kiểm tra:

```bash
cd app && flutter build macos --release
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" build/macos/Build/Products/Release/SimDeck.app/Contents/Info.plist
```

- [ ] **Step 5: Viết cask** — `packaging/Casks/simdeck.rb` đúng nội dung §12.1 của spec (cask `simdeck`, `depends_on formula: "ffmpeg"`, `depends_on cask: "android-platform-tools"`, `caveats` nêu `xattr`).

- [ ] **Step 6: Kiểm chứng đường cài thật**

```bash
bash scripts/release.sh 0.1.0
brew install --cask ./build/SimDeck-0.1.0.dmg
open /Applications/SimDeck.app            # mở được, không có nút update
brew uninstall --cask simdeck && ls /Applications | grep -c SimDeck   # 0
```

- [ ] **Step 7: Commit** — `git commit -am "build: brew cask packaging, disable self-update, rebrand to SimDeck"`

---

## Nghiệm thu cuối (chạy đủ 10 mục §11 của spec)

Sau Task 13, chạy lại toàn bộ danh sách nghiệm thu trong spec trên bản cài bằng brew, gồm:
tạo/sửa/start/stop/wipe/delete AVD `ZZ_*`, tạo và chạy simulator iOS `ZZ_*`, cài một image mới,
chặn thư mục chia sẻ, và checksum `config.ini` của `E2` không đổi.
