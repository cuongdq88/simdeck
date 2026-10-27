import 'package:flutter/foundation.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';

/// Which platform the create form is building for.
enum FormPlatform { android, ios }

/// "Pixel 9 (Google)" + 36 → "Pixel 9 API 36", the name avdmanager gets
/// unless the user types another.
String suggestName(AvdProfile profile, int api) =>
    '${profile.name.split(' (').first} API $api';

/// The fields both the Create and the Edit sheet edit. Immutable: every
/// change replaces it, so the sheet can rebuild from one value.
class CreateDeviceForm {
  const CreateDeviceForm({
    this.platform = FormPlatform.android,
    this.name = '',
    this.profile,
    this.api,
    this.tag,
    this.ramMb,
    this.storage,
    this.camera,
    this.orientation,
    this.keyboard,
    this.sdcard,
    this.advanced = false,
    this.iosDeviceType,
    this.iosRuntime,
  });

  final FormPlatform platform;
  final String name;
  final AvdProfile? profile;
  final int? api;
  final AvdTag? tag;
  final int? ramMb;
  final String? storage;
  final String? camera;
  final String? orientation;
  final bool? keyboard;
  final String? sdcard;
  final bool advanced;
  final IosDeviceType? iosDeviceType;
  final IosRuntime? iosRuntime;
}

/// Drives the Create / Edit Device sheet: loads the catalogs, keeps the form
/// valid, and calls the helper.
class CreateDeviceController extends ChangeNotifier {
  CreateDeviceController({required this.bridge, AvdConfig? editing})
    : _editing = editing,
      _form = editing == null
          ? const CreateDeviceForm()
          : CreateDeviceForm(
              name: editing.name,
              api: editing.api,
              ramMb: editing.ram,
              storage: editing.storage,
              camera: editing.camera,
              orientation: editing.orientation,
              keyboard: editing.keyboard,
              sdcard: editing.sdcard,
            ) {
    notifyListeners();
  }

  factory CreateDeviceController.forCreate({EmuBridge? bridge}) =>
      CreateDeviceController(
        bridge: bridge ?? EmuBridge(emuPath: EmuBridge.resolveEmuPath()),
      );

  factory CreateDeviceController.forEdit(
    AvdConfig config, {
    EmuBridge? bridge,
  }) => CreateDeviceController(
    bridge: bridge ?? EmuBridge(emuPath: EmuBridge.resolveEmuPath()),
    editing: config,
  );

  static final _namePattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

  /// Everything the Create form can set.
  static const _createFields = {
    'name',
    'platform',
    'profile',
    'api',
    'tag',
    'ram',
    'storage',
    'camera',
    'orientation',
    'keyboard',
    'sdcard',
  };

  /// Edit keeps the image identity locked, exactly like Studio: changing
  /// profile/API/tag/ABI means a different AVD.
  static const _editFields = {
    'ram',
    'storage',
    'camera',
    'orientation',
    'keyboard',
    'sdcard',
  };

  final EmuBridge bridge;
  final AvdConfig? _editing;
  CreateDeviceForm _form;

  List<AvdProfile> profiles = const [];
  List<AvdTag> tags = const [];
  List<IosDeviceType> iosDeviceTypes = const [];
  List<IosRuntime> iosRuntimes = const [];
  List<ImagePackage> images = const [];

  bool loading = false;
  bool submitting = false;
  String? error;
  String? errorCode;
  String? createdName;

  CreateDeviceForm get form => _form;

  bool get isEditing => _editing != null;

  Set<String> get editable => isEditing ? _editFields : _createFields;

  String? get nameError {
    if (_form.name.isEmpty) return null;
    return _namePattern.hasMatch(_form.name) ? null : 'Use letters, digits, dot, dash or underscore (max 64)';
  }

  bool get canSubmit {
    if (submitting || _form.name.isEmpty || nameError != null) return false;
    if (_form.platform == FormPlatform.ios) {
      return _form.iosDeviceType != null && _form.iosRuntime != null;
    }
    if (isEditing) return true;
    return _form.profile != null &&
        _form.api != null &&
        (_form.tag?.installed ?? false);
  }

  /// APIs that have an installed image, newest first.
  List<int> get installedApis {
    final apis = <int>{
      for (final image in images)
        if (image.installed) ?int.tryParse(image.api),
    }.toList()..sort((a, b) => b.compareTo(a));
    return apis;
  }

  /// "Needs about 10.3 GB free", from the selected image plus the 8 GiB
  /// headroom the helper enforces; null until an image is picked.
  String? get requiredSpaceLabel {
    final tag = _form.tag;
    if (tag == null || _form.api == null) return null;
    final package = 'system-images;android-${_form.api};${tag.tag};${tag.abi}';
    for (final image in images) {
      if (image.package == package) {
        final gb = (image.sizeBytes / (1 << 30)) + 8;
        return 'Needs about ${gb.toStringAsFixed(1)} GB free';
      }
    }
    return null;
  }

  /// Profiles and the iOS catalogs in parallel; one failing catalog does not
  /// stop the others from filling the form.
  Future<void> loadCatalogs() async {
    loading = true;
    _notify();
    final results = await Future.wait<Object>([
      bridge.avdProfiles().catchError((Object _) => const <AvdProfile>[]),
      bridge.iosDeviceTypes().catchError((Object _) => const <IosDeviceType>[]),
      bridge.iosRuntimes().catchError((Object _) => const <IosRuntime>[]),
      bridge.images().catchError((Object _) => const <ImagePackage>[]),
    ]);
    profiles = results[0] as List<AvdProfile>;
    iosDeviceTypes = results[1] as List<IosDeviceType>;
    iosRuntimes = results[2] as List<IosRuntime>;
    images = results[3] as List<ImagePackage>;
    loading = false;
    if (isEditing && _form.api != null) {
      await loadTags(_form.api!);
    }
    _notify();
  }

  Future<void> loadTags(int api) async {
    try {
      tags = await bridge.avdTags(api);
    } on EmuException catch (e) {
      tags = const [];
      error = _describe(e);
      errorCode = e.code;
    }
    _notify();
  }

  void setPlatform(FormPlatform platform) {
    _form = _copy(platform: platform);
    _notify();
  }

  void setName(String name) {
    _form = _copy(name: name);
    _notify();
  }

  void setProfile(AvdProfile profile) {
    _form = _copy(
      profile: profile,
      name: _form.name.isEmpty && _form.api != null
          ? suggestName(profile, _form.api!)
          : _form.name,
    );
    _notify();
  }

  void setApi(int api) {
    _form = _copy(
      api: api,
      name: _form.profile == null || _form.name.isNotEmpty
          ? _form.name
          : suggestName(_form.profile!, api),
    );
    _notify();
  }

  void setTag(AvdTag tag) {
    _form = _copy(tag: tag);
    _notify();
  }

  void setRam(int? ram) {
    _form = _copy(ramMb: ram);
    _notify();
  }

  void setStorage(String? storage) {
    _form = _copy(storage: storage);
    _notify();
  }

  void setCamera(String? camera) {
    _form = _copy(camera: camera);
    _notify();
  }

  void setOrientation(String? orientation) {
    _form = _copy(orientation: orientation);
    _notify();
  }

  void setKeyboard(bool? keyboard) {
    _form = _copy(keyboard: keyboard);
    _notify();
  }

  void setSdcard(String? sdcard) {
    _form = _copy(sdcard: sdcard);
    _notify();
  }

  void setAdvanced(bool advanced) {
    _form = _copy(advanced: advanced);
    _notify();
  }

  void setIosDeviceType(IosDeviceType type) {
    _form = _copy(iosDeviceType: type);
    _notify();
  }

  void setIosRuntime(IosRuntime runtime) {
    _form = _copy(iosRuntime: runtime);
    _notify();
  }

  /// Creates (Android or iOS) or updates (Android); errors land in [error]
  /// so the sheet can show them instead of throwing.
  Future<void> submit() async {
    if (!canSubmit) return;
    submitting = true;
    error = null;
    errorCode = null;
    _notify();
    try {
      if (_form.platform == FormPlatform.ios) {
        await bridge.run(
          [
            'ios',
            'create',
            '--device-type',
            _form.iosDeviceType!.id,
            '--runtime',
            _form.iosRuntime!.id,
            '--name',
            _form.name,
          ],
          (json) => json,
        );
      } else if (isEditing) {
        await bridge.run(_updateArgs(), (json) => json);
      } else {
        await bridge.run(_createArgs(), (json) => json);
      }
      createdName = _form.name;
    } on EmuException catch (e) {
      error = _describe(e);
      errorCode = e.code;
    } finally {
      submitting = false;
      _notify();
    }
  }

  List<String> _createArgs() => [
    'avd',
    'create',
    '--name',
    _form.name,
    '--api',
    '${_form.api}',
    '--tag',
    _form.tag!.tag,
    '--abi',
    _form.tag!.abi,
    '--device',
    _form.profile!.id,
    if (_form.ramMb != null) ...['--ram', '${_form.ramMb}'],
    if (_form.storage case final storage?) ...['--storage', storage],
    if (_form.camera case final camera?) ...['--camera', camera],
    if (_form.orientation case final orientation?) ...[
      '--orientation',
      orientation,
    ],
    if (_form.keyboard case final keyboard?) ...[
      '--keyboard',
      '$keyboard',
    ],
  ];

  List<String> _updateArgs() => [
    'avd',
    'update',
    '--name',
    _form.name,
    if (_form.ramMb != null) ...['--ram', '${_form.ramMb}'],
    if (_form.storage case final storage?) ...['--storage', storage],
    if (_form.camera case final camera?) ...['--camera', camera],
    if (_form.orientation case final orientation?) ...[
      '--orientation',
      orientation,
    ],
    if (_form.keyboard case final keyboard?) ...[
      '--keyboard',
      '$keyboard',
    ],
    if (_form.sdcard case final sdcard?) ...['--sdcard', sdcard],
  ];

  static String _describe(EmuException e) =>
      e.hint == null ? e.message : '${e.message} — ${e.hint}';

  CreateDeviceForm _copy({
    FormPlatform? platform,
    String? name,
    AvdProfile? profile,
    int? api,
    AvdTag? tag,
    int? ramMb,
    String? storage,
    String? camera,
    String? orientation,
    bool? keyboard,
    String? sdcard,
    bool? advanced,
    IosDeviceType? iosDeviceType,
    IosRuntime? iosRuntime,
  }) => CreateDeviceForm(
    platform: platform ?? _form.platform,
    name: name ?? _form.name,
    profile: profile ?? _form.profile,
    api: api ?? _form.api,
    tag: tag ?? _form.tag,
    ramMb: ramMb ?? _form.ramMb,
    storage: storage ?? _form.storage,
    camera: camera ?? _form.camera,
    orientation: orientation ?? _form.orientation,
    keyboard: keyboard ?? _form.keyboard,
    sdcard: sdcard ?? _form.sdcard,
    advanced: advanced ?? _form.advanced,
    iosDeviceType: iosDeviceType ?? _form.iosDeviceType,
    iosRuntime: iosRuntime ?? _form.iosRuntime,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
