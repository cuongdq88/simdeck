import 'package:flutter/foundation.dart';
import 'package:simutil_shared/simutil_shared.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';

/// What the Runtime Manager needs from the helper; separate from
/// [EmuBridge] so tests can answer with canned streams.
abstract interface class RuntimeApi {
  Future<List<ImagePackage>> images({String platform});
  Stream<InstallProgress> install(String package);
  Stream<InstallProgress> acceptLicenses();
  Future<void> uninstall(String package);
}

/// [EmuBridge] behind [RuntimeApi].
class EmuRuntimeApi implements RuntimeApi {
  const EmuRuntimeApi(this.bridge);

  final EmuBridge bridge;

  @override
  Future<List<ImagePackage>> images({String platform = 'android'}) =>
      bridge.images(platform: platform);

  @override
  Stream<InstallProgress> install(String package) => bridge.install(package);

  @override
  Stream<InstallProgress> acceptLicenses() => bridge.acceptLicenses();

  @override
  Future<void> uninstall(String package) => bridge.run(
    ['images', 'uninstall', '--package', package],
    (json) => json,
  );
}

/// Drives the Runtime Manager: install with progress, uninstall behind the
/// deletion guard, and the license prompt (spec §9.3).
class RuntimeManagerController extends ChangeNotifier {
  RuntimeManagerController({required this.api, DeletionGuard? guard})
    : _guard = guard;

  final RuntimeApi api;
  final DeletionGuard? _guard;

  List<ImagePackage> images = const [];
  Set<String> installed = const {};
  bool loading = false;
  int progress = 0;
  String progressMessage = '';
  String? installing;
  bool licensesRequired = false;
  String? error;
  String? errorCode;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      images = await api.images();
      installed = {
        for (final image in images)
          if (image.installed) image.package,
      };
      error = null;
    } on EmuException catch (e) {
      error = _describe(e);
      errorCode = e.code;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> install(String package) async {
    installing = package;
    progress = 0;
    progressMessage = '';
    licensesRequired = false;
    error = null;
    errorCode = null;
    notifyListeners();
    try {
      await for (final event in api.install(package)) {
        progress = event.percent;
        progressMessage = event.message;
        notifyListeners();
      }
      installed = {...installed, package};
      progress = 100;
      if (!images.any((image) => image.package == package)) {
        await load();
      }
    } on EmuException catch (e) {
      if (e.code == 'license_required') {
        licensesRequired = true;
        error = _describe(e);
        errorCode = e.code;
      } else {
        error = _describe(e);
        errorCode = e.code;
      }
    } finally {
      installing = null;
      notifyListeners();
    }
  }

  Future<void> acceptLicenses() async {
    try {
      await for (final event in api.acceptLicenses()) {
        progress = event.percent;
        progressMessage = event.message;
        notifyListeners();
      }
      licensesRequired = false;
      error = null;
      errorCode = null;
    } on EmuException catch (e) {
      error = _describe(e);
      errorCode = e.code;
    }
    notifyListeners();
  }

  /// Refuses to uninstall an image an AVD still boots from, listing those
  /// AVDs instead.
  Future<void> uninstall(String package) async {
    error = null;
    errorCode = null;
    final verdict = await _guard?.checkImage(package);
    if (verdict != null && !verdict.allowed) {
      error = verdict.message;
      errorCode = verdict.code;
      notifyListeners();
      return;
    }
    try {
      await api.uninstall(package);
      installed = {...installed}..remove(package);
      images = [
        for (final image in images)
          if (image.package == package)
            ImagePackage(
              package: image.package,
              api: image.api,
              tag: image.tag,
              abi: image.abi,
              installed: false,
              sizeBytes: image.sizeBytes,
            )
          else
            image,
      ];
    } on EmuException catch (e) {
      error = _describe(e);
      errorCode = e.code;
    }
    notifyListeners();
  }

  static String _describe(EmuException e) =>
      e.hint == null ? e.message : '${e.message} — ${e.hint}';
}
