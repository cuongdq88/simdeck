/// The `emu --json` payloads, decoded.
library;

class AvdProfile {
  const AvdProfile({
    required this.id,
    required this.name,
    this.width = 0,
    this.height = 0,
    this.density = 0,
  });

  factory AvdProfile.fromJson(Object? json) {
    final map = json as Map;
    return AvdProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      density: (map['density'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final int width;
  final int height;
  final int density;

  /// "1080 × 2424", or empty when the SDK has no skin for this profile.
  String get screen => width > 0 && height > 0 ? '$width × $height' : '';
}

class AvdTag {
  const AvdTag({required this.tag, required this.abi, required this.installed});

  factory AvdTag.fromJson(Object? json) {
    final map = json as Map;
    return AvdTag(
      tag: map['tag'] as String,
      abi: map['abi'] as String,
      installed: map['installed'] as bool? ?? false,
    );
  }

  final String tag;
  final String abi;
  final bool installed;
}

class IosDeviceType {
  const IosDeviceType({required this.id, required this.name});

  factory IosDeviceType.fromJson(Object? json) {
    final map = json as Map;
    return IosDeviceType(
      id: map['id'] as String,
      name: map['name'] as String,
    );
  }

  final String id;
  final String name;
}

class IosRuntime {
  const IosRuntime({required this.id, required this.name, required this.version});

  factory IosRuntime.fromJson(Object? json) {
    final map = json as Map;
    return IosRuntime(
      id: map['id'] as String,
      name: map['name'] as String,
      version: map['version'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String version;
}

/// One system image / runtime row of the Runtime Manager.
class ImagePackage {
  const ImagePackage({
    required this.package,
    required this.api,
    required this.tag,
    required this.abi,
    required this.installed,
    this.sizeBytes = 0,
  });

  factory ImagePackage.fromJson(Object? json) {
    final map = json as Map;
    return ImagePackage(
      package: map['package'] as String,
      api: map['api'] as String? ?? '',
      tag: map['tag'] as String? ?? '',
      abi: map['abi'] as String? ?? '',
      installed: map['installed'] as bool? ?? false,
      sizeBytes: (map['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String package;
  final String api;
  final String tag;
  final String abi;
  final bool installed;
  final int sizeBytes;

  /// "1.2 GB", or empty when the size is unknown.
  String get sizeLabel => sizeBytes <= 0
      ? ''
      : sizeBytes >= 1 << 30
      ? '${(sizeBytes / (1 << 30)).toStringAsFixed(1)} GB'
      : '${(sizeBytes / (1 << 20)).round()} MB';
}

/// An AVD as the Edit sheet sees it: the locked image fields plus the
/// editable ones.
class AvdConfig {
  const AvdConfig({
    this.name = '',
    this.path = '',
    this.ram,
    this.api,
    this.tag = '',
    this.abi = '',
    this.storage,
    this.camera,
    this.orientation,
    this.keyboard,
    this.sdcard,
  });

  factory AvdConfig.fromShow(Object? json) {
    final map = json as Map;
    final config = (map['config'] as Map?) ?? const {};
    final editable = (map['editable'] as Map?) ?? const {};
    final target = config['target'] as String? ?? '';
    return AvdConfig(
      name: map['name'] as String? ?? '',
      path: map['path'] as String? ?? '',
      ram: (editable['ram'] as num?)?.toInt(),
      api: int.tryParse(target.replaceFirst('android-', '')),
      tag: config['tag.id'] as String? ?? '',
      abi: config['abi.type'] as String? ?? '',
      storage: editable['storage'] as String?,
      camera: editable['camera'] as String?,
      orientation: editable['orientation'] as String?,
      keyboard: editable['keyboard'] as bool?,
      sdcard: editable['sdcard'] as String?,
    );
  }

  final String name;
  final String path;
  final int? ram;
  final int? api;
  final String tag;
  final String abi;
  final String? storage;
  final String? camera;
  final String? orientation;
  final bool? keyboard;
  final String? sdcard;
}

/// One NDJSON progress line of an install.
class InstallProgress {
  const InstallProgress({required this.percent, required this.message});

  final int percent;
  final String message;
}

/// `emu --json env check`, flattened for the Environment panel.
class EnvironmentReport {
  const EnvironmentReport({
    required this.sdkPath,
    required this.avdHome,
    required this.adb,
    required this.emulator,
    required this.avdmanager,
    required this.sdkmanager,
    required this.xcode,
    required this.licensesAccepted,
    this.diskFreeBytes,
  });

  factory EnvironmentReport.fromJson(Object? json) {
    final map = json as Map;
    final tools = (map['tools'] as Map?) ?? const {};
    final xcode = (map['xcode'] as Map?) ?? const {};
    String? version(Object? tool) {
      if (tool is! Map) return null;
      final value = tool['version'] as String?;
      return value ?? (tool['path'] as String?);
    }

    return EnvironmentReport(
      sdkPath: map['sdk_path'] as String? ?? '',
      avdHome: map['avd_home'] as String? ?? '',
      adb: version(tools['adb']),
      emulator: version(tools['emulator']),
      avdmanager: version(tools['avdmanager']),
      sdkmanager: version(tools['sdkmanager']),
      xcode: xcode['present'] == true
          ? xcode['version'] as String? ?? 'present'
          : null,
      licensesAccepted: map['licenses_accepted'] as bool? ?? false,
      diskFreeBytes: (map['disk_free_bytes'] as num?)?.toInt(),
    );
  }

  final String sdkPath;
  final String avdHome;
  final String? adb;
  final String? emulator;
  final String? avdmanager;
  final String? sdkmanager;
  final String? xcode;
  final bool licensesAccepted;
  final int? diskFreeBytes;

  String get diskFreeLabel {
    final bytes = diskFreeBytes;
    if (bytes == null) return 'unknown';
    return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  }
}
