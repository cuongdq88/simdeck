import 'dart:io';

/// One `<name>.ini` in the AVD home, resolved to the directory it points at.
class IniFile {
  const IniFile(this.name, this.dirPath);

  final String name;
  final String dirPath;
}

/// Whether the app may destroy something, and why not.
class GuardVerdict {
  const GuardVerdict.allow()
    : allowed = true,
      code = null,
      message = null;

  const GuardVerdict.block(this.code, this.message) : allowed = false;

  final bool allowed;
  final String? code;
  final String? message;
}

/// Supplies the AVD names that are running right now.
typedef RunningAvdLoader = Future<Set<String>> Function();

/// Refuses the destructive operations that have bitten this machine before
/// (spec §10): two `.ini` files sharing one AVD directory, a running AVD,
/// and an image an AVD still boots from.
class DeletionGuard {
  DeletionGuard({
    required Set<String> runningAvds,
    required List<IniFile> iniFiles,
    Map<String, String> avdImages = const {},
    RunningAvdLoader? runningAvdsLoader,
  }) : _runningAvds = runningAvds,
       _iniFiles = iniFiles,
       _avdImages = avdImages,
       _runningAvdsLoader = runningAvdsLoader;

  factory DeletionGuard.fromFiles(List<IniFile> files) =>
      DeletionGuard(runningAvds: const {}, iniFiles: files);

  /// Reads `$ANDROID_AVD_HOME` (or `~/.android/avd`), each `.ini`'s `path=`
  /// and each AVD's `image.sysdir.1`.
  factory DeletionGuard.load({
    String? avdHome,
    RunningAvdLoader? runningAvdsLoader,
  }) {
    final home =
        avdHome ??
        Platform.environment['ANDROID_AVD_HOME'] ??
        '${Platform.environment['HOME']}/.android/avd';
    final files = <IniFile>[];
    final images = <String, String>{};
    final directory = Directory(home);
    if (!directory.existsSync()) {
      return DeletionGuard(
        runningAvds: const {},
        iniFiles: files,
        runningAvdsLoader: runningAvdsLoader,
      );
    }
    for (final entry in directory.listSync()) {
      if (entry is! File || !entry.path.endsWith('.ini')) continue;
      final name = entry.uri.pathSegments.last.replaceFirst('.ini', '');
      final body = entry.readAsStringSync();
      final relative = RegExp(
        r'^path\.rel=(.*)$',
        multiLine: true,
      ).firstMatch(body)?.group(1)?.trim();
      final absolute = RegExp(
        r'^path=(.*)$',
        multiLine: true,
      ).firstMatch(body)?.group(1)?.trim();
      final dir = absolute ?? (relative == null ? '$home/$name.avd' : '$home/$relative');
      files.add(IniFile(name, dir));
      final config = File('$dir/config.ini');
      if (!config.existsSync()) continue;
      final image = RegExp(
        r'^image\.sysdir\.1=(.*)$',
        multiLine: true,
      ).firstMatch(config.readAsStringSync())?.group(1)?.trim();
      if (image != null) images[name] = _imagePackage(image);
    }
    return DeletionGuard(
      runningAvds: const {},
      iniFiles: files,
      avdImages: images,
      runningAvdsLoader: runningAvdsLoader,
    );
  }

  final Set<String> _runningAvds;
  final List<IniFile> _iniFiles;
  final Map<String, String> _avdImages;
  final RunningAvdLoader? _runningAvdsLoader;

  /// `system-images/android-36/tag/abi/` → `system-images;android-36;tag;abi`.
  static String _imagePackage(String sysdir) {
    final trimmed = sysdir
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    return trimmed.replaceAll('/', ';');
  }

  static String _normalize(String path) {
    final trimmed = path.replaceFirst(RegExp(r'/+$'), '');
    try {
      return Directory(trimmed).resolveSymbolicLinksSync();
    } on FileSystemException {
      return trimmed;
    }
  }

  Future<GuardVerdict> checkAvd(String name) async {
    final wanted = _iniFiles.where((file) => file.name == name).firstOrNull;
    if (wanted == null) {
      return const GuardVerdict.block(
        'not_found',
        'This AVD is no longer on disk; refresh the list.',
      );
    }

    final target = _normalize(wanted.dirPath);
    final sharing = [
      for (final file in _iniFiles)
        if (file.name != name && _normalize(file.dirPath) == target) file.name,
    ];
    if (sharing.isNotEmpty) {
      final names = [name, ...sharing].join(', ');
      return GuardVerdict.block(
        'shared_dir',
        'Blocked: $names all point at ${wanted.dirPath}. Deleting one would '
        'destroy the others.',
      );
    }

    final running = await _currentRunningAvds();
    if (running.contains(name)) {
      return GuardVerdict.block(
        'device_running',
        'Stop $name before deleting or wiping it.',
      );
    }
    return const GuardVerdict.allow();
  }

  Future<GuardVerdict> checkImage(String package) async {
    final users = [
      for (final entry in _avdImages.entries)
        if (entry.value == package) entry.key,
    ];
    if (users.isEmpty) return const GuardVerdict.allow();
    return GuardVerdict.block(
      'image_in_use',
      'Blocked: ${users.join(', ')} ${users.length == 1 ? 'boots' : 'boot'} '
      'from this image. Delete the AVD${users.length == 1 ? '' : 's'} first.',
    );
  }

  Future<Set<String>> _currentRunningAvds() async =>
      await _runningAvdsLoader?.call() ?? _runningAvds;
}
