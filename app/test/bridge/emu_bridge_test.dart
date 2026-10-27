import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';

/// Answers with canned process results; [lines] feeds [stream].
class FakeRunner implements ProcessRunner {
  FakeRunner({this.result, this.lines = const []});

  final ProcessResult? result;
  final List<String> lines;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add([exe, ...args]);
    return result ?? ProcessResult(0, 0, '{"ok":true,"data":null,"error":null}', '');
  }

  @override
  Stream<String> stream(String exe, List<String> args) {
    calls.add([exe, ...args]);
    return Stream.fromIterable(lines);
  }
}

void main() {
  test('maps error envelope to EmuException', () async {
    final bridge = EmuBridge(
      emuPath: 'emu',
      runner: FakeRunner(
        result: ProcessResult(
          1,
          1,
          '{"ok":false,"data":null,"error":{"code":"image_missing","message":"m","hint":"h"}}',
          '',
        ),
      ),
    );
    await expectLater(
      bridge.run(['avd', 'create'], (json) => json),
      throwsA(
        isA<EmuException>()
            .having((e) => e.code, 'code', 'image_missing')
            .having((e) => e.hint, 'hint', 'h'),
      ),
    );
  });

  test('surfaces non-json stdout as tool_failed', () async {
    final bridge = EmuBridge(
      emuPath: 'emu',
      runner: FakeRunner(result: ProcessResult(2, 1, 'boom: not json', '')),
    );
    await expectLater(
      bridge.run(['env', 'check'], (json) => json),
      throwsA(
        isA<EmuException>().having((e) => e.code, 'code', 'tool_failed'),
      ),
    );
  });

  test('returns the decoded data of an ok envelope', () async {
    final bridge = EmuBridge(
      emuPath: 'emu',
      runner: FakeRunner(
        result: ProcessResult(
          1,
          0,
          'noise line\n{"ok":true,"data":{"sdk_path":"/sdk"},"error":null}\n',
          '',
        ),
      ),
    );
    final data = await bridge.run(
      ['env', 'check'],
      (json) => (json as Map)['sdk_path'] as String,
    );
    expect(data, '/sdk');
  });

  test('passes --json to every command', () async {
    final runner = FakeRunner();
    await EmuBridge(emuPath: 'emu', runner: runner).run(['env', 'check'], (j) => j);
    expect(runner.calls.single.first, 'emu');
    expect(runner.calls.single, contains('--json'));
  });

  test('streams install progress and ends at 100', () async {
    final bridge = EmuBridge(
      emuPath: 'emu',
      runner: FakeRunner(
        lines: [
          '{"event":"progress","percent":0,"message":"Installing p"}',
          '{"event":"progress","percent":50,"message":"Unzipping"}',
          '{"event":"done","ok":true,"data":{"package":"p","installed":true},"error":null}',
        ],
      ),
    );
    final percents = await bridge.install('p').map((p) => p.percent).toList();
    expect(percents, [0, 50]);
  });

  test('install turns a failed done line into EmuException', () async {
    final bridge = EmuBridge(
      emuPath: 'emu',
      runner: FakeRunner(
        lines: [
          '{"event":"done","ok":false,"data":null,"error":{"code":"license_required","message":"licenses","hint":null}}',
        ],
      ),
    );
    await expectLater(
      bridge.install('p').toList(),
      throwsA(
        isA<EmuException>().having((e) => e.code, 'code', 'license_required'),
      ),
    );
  });

  test('parses catalogs and the editable config', () {
    final profile = AvdProfile.fromJson({
      'id': 'pixel_9',
      'name': 'Pixel 9 (Google)',
      'width': 1080,
      'height': 2424,
      'density': 420,
    });
    expect(profile.screen, '1080 × 2424');

    final config = AvdConfig.fromShow({
      'name': 'ZZ_Test',
      'path': '/avd/ZZ_Test.avd',
      'config': {'hw.ramSize': '2048', 'disk.dataPartition.size': '8G', 'target': 'android-36'},
      'editable': {
        'ram': 2048,
        'storage': '8G',
        'camera': 'virtualscene',
        'orientation': 'portrait',
        'keyboard': false,
        'sdcard': null,
      },
    });
    expect(config.name, 'ZZ_Test');
    expect(config.ram, 2048);
    expect(config.api, 36);
    expect(config.storage, '8G');
    expect(config.keyboard, isFalse);
  });
}
