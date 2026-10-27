import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/bridge/deletion_guard.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/ui/runtimes/runtime_manager_controller.dart';

class _FakeApi implements RuntimeApi {
  _FakeApi({this.installEvents = const [], this.licenseError = false});

  final List<InstallProgress> installEvents;
  final bool licenseError;
  final installed = <String>{};
  final uninstalled = <String>[];
  int licensesAccepted = 0;

  @override
  Future<List<ImagePackage>> images({String platform = 'android'}) async => [
    for (final package in ['pkg', 'other'])
      ImagePackage(
        package: package,
        api: '35',
        tag: 'google_apis',
        abi: 'arm64-v8a',
        installed: installed.contains(package) || package == 'other',
      ),
  ];

  @override
  Stream<InstallProgress> install(String package) async* {
    for (final event in installEvents) {
      yield event;
    }
    if (licenseError) {
      throw const EmuException(
        'license_required',
        'SDK licenses not accepted',
        hint: 'Run licenses accept',
      );
    }
    installed.add(package);
  }

  @override
  Stream<InstallProgress> acceptLicenses() async* {
    licensesAccepted++;
    yield const InstallProgress(percent: 100, message: 'accepted');
  }

  @override
  Future<void> uninstall(String package) async {
    uninstalled.add(package);
    installed.remove(package);
  }
}

void main() {
  test('license error flips licensesRequired instead of throwing', () async {
    final c = RuntimeManagerController(api: _FakeApi(licenseError: true));
    await c.install('system-images;android-35;google_apis;arm64-v8a');
    expect(c.licensesRequired, isTrue);
    expect(c.progress, 0);
    expect(c.installing, isNull);
  });

  test('progress reaches 100 then marks installed', () async {
    final c = RuntimeManagerController(
      api: _FakeApi(
        installEvents: const [
          InstallProgress(percent: 0, message: 'start'),
          InstallProgress(percent: 50, message: 'unzip'),
          InstallProgress(percent: 100, message: 'done'),
        ],
      ),
    );
    await c.install('pkg');
    expect(c.progress, 100);
    expect(c.installed.contains('pkg'), isTrue);
  });

  test('load marks what the helper lists as installed', () async {
    final c = RuntimeManagerController(api: _FakeApi());
    await c.load();
    expect(c.installed, {'other'});
    expect(c.images.length, 2);
  });

  test('accepting licenses clears the flag', () async {
    final api = _FakeApi(licenseError: true);
    final c = RuntimeManagerController(api: api);
    await c.install('pkg');
    expect(c.licensesRequired, isTrue);
    await c.acceptLicenses();
    expect(c.licensesRequired, isFalse);
    expect(api.licensesAccepted, 1);
  });

  test('uninstall is blocked while an AVD boots from the image', () async {
    final api = _FakeApi();
    final c = RuntimeManagerController(
      api: api,
      guard: DeletionGuard(
        runningAvds: const {},
        iniFiles: const [],
        avdImages: const {
          'ZZ_Test': 'system-images;android-35;google_apis;arm64-v8a',
        },
      ),
    );
    await c.uninstall('system-images;android-35;google_apis;arm64-v8a');
    expect(api.uninstalled, isEmpty);
    expect(c.error, contains('ZZ_Test'));
    expect(c.errorCode, 'image_in_use');
  });

  test('uninstall is allowed when nothing uses the image', () async {
    final api = _FakeApi();
    final c = RuntimeManagerController(api: api);
    await c.uninstall('pkg');
    expect(api.uninstalled, ['pkg']);
    expect(c.error, isNull);
  });
}
