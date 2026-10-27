import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/bridge/deletion_guard.dart';

void main() {
  test('blocks delete when two ini share one avd dir', () async {
    final guard = DeletionGuard.fromFiles([
      const IniFile('E1', '/Users/x/.android/avd/Pixel_9_Pro_XL.avd'),
      const IniFile(
        'Pixel_9_Pro_XL',
        '/Users/x/.android/avd/Pixel_9_Pro_XL.avd',
      ),
    ]);
    final verdict = await guard.checkAvd('E1');
    expect(verdict.allowed, isFalse);
    expect(verdict.code, 'shared_dir');
    expect(verdict.message, contains('Pixel_9_Pro_XL'));
  });

  test('blocks when device is running', () async {
    final guard = DeletionGuard(
      runningAvds: {'ZZ_Test'},
      iniFiles: [const IniFile('ZZ_Test', '/p/ZZ_Test.avd')],
    );
    expect((await guard.checkAvd('ZZ_Test')).code, 'device_running');
  });

  test('allows a lone, stopped AVD', () async {
    final guard = DeletionGuard.fromFiles([
      const IniFile('ZZ_Test', '/p/ZZ_Test.avd'),
    ]);
    expect((await guard.checkAvd('ZZ_Test')).allowed, isTrue);
  });

  test('reports an unknown AVD as not_found', () async {
    final guard = DeletionGuard.fromFiles(const []);
    expect((await guard.checkAvd('Missing')).code, 'not_found');
  });

  test('blocks uninstalling an image an AVD boots from', () async {
    final guard = DeletionGuard(
      runningAvds: const {},
      iniFiles: const [IniFile('ZZ_Test', '/p/ZZ_Test.avd')],
      avdImages: const {
        'ZZ_Test': 'system-images;android-36;google_apis_playstore;arm64-v8a',
      },
    );
    final verdict = await guard.checkImage(
      'system-images;android-36;google_apis_playstore;arm64-v8a',
    );
    expect(verdict.allowed, isFalse);
    expect(verdict.code, 'image_in_use');
    expect(verdict.message, contains('ZZ_Test'));
  });

  test('allows uninstalling an unused image', () async {
    final guard = DeletionGuard(
      runningAvds: const {},
      iniFiles: const [IniFile('ZZ_Test', '/p/ZZ_Test.avd')],
      avdImages: const {
        'ZZ_Test': 'system-images;android-36;google_apis_playstore;arm64-v8a',
      },
    );
    expect(
      (await guard.checkImage(
        'system-images;android-35;google_apis;arm64-v8a',
      )).allowed,
      isTrue,
    );
  });

  test('load reads ini files and their image from a real directory', () async {
    final home = await Directory.systemTemp.createTemp('simdeck-avd');
    addTearDown(() => home.delete(recursive: true));
    final avdDir = Directory('${home.path}/ZZ_Test.avd')..createSync();
    File(
      '${home.path}/ZZ_Test.ini',
    ).writeAsStringSync('path=${avdDir.path}\n');
    File('${avdDir.path}/config.ini').writeAsStringSync(
      'image.sysdir.1=system-images/android-36/google_apis_playstore/arm64-v8a/\n',
    );

    final guard = DeletionGuard.load(avdHome: home.path);
    expect((await guard.checkAvd('ZZ_Test')).allowed, isTrue);
    final verdict = await guard.checkImage(
      'system-images;android-36;google_apis_playstore;arm64-v8a',
    );
    expect(verdict.code, 'image_in_use');
  });
}
