import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/ui/create/create_device_controller.dart';

class FakeRunner implements ProcessRunner {
  FakeRunner(this.answers);

  /// Answers keyed by the joined args, first matching prefix wins.
  final Map<String, String> answers;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add([exe, ...args]);
    for (final entry in answers.entries) {
      if (args.join(' ').contains(entry.key)) {
        return ProcessResult(0, 0, entry.value, '');
      }
    }
    return ProcessResult(1, 1, '{"ok":false,"data":null,"error":{"code":"tool_failed","message":"unexpected"}', '');
  }

  @override
  Stream<String> stream(String exe, List<String> args) => const Stream.empty();
}

const _profiles = '{"ok":true,"data":[{"id":"pixel_9","name":"Pixel 9 (Google)","width":1080,"height":2424,"density":420}],"error":null}';
const _tags = '{"ok":true,"data":[{"tag":"google_apis_playstore","abi":"arm64-v8a","installed":true}],"error":null}';
const _deviceTypes = '{"ok":true,"data":[{"id":"com.apple.CoreSimulator.SimDeviceType.iPhone-17","name":"iPhone 17"}],"error":null}';
const _runtimes = '{"ok":true,"data":[{"id":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","name":"iOS 26.5","version":"26.5"}],"error":null}';

CreateDeviceController controller(EmuBridge bridge) => CreateDeviceController(
  bridge: bridge,
  editing: null,
);

void main() {
  test('edit mode locks image fields but allows ram', () {
    final c = CreateDeviceController.forEdit(
      const AvdConfig(ram: 2048, api: 36, tag: 'google_apis_playstore'),
    );
    expect(c.editable.contains('ram'), isTrue);
    expect(c.editable.contains('tag'), isFalse);
  });

  test('cannot submit while a required field is empty', () {
    final c = CreateDeviceController.forCreate();
    expect(c.canSubmit, isFalse);
  });

  test('suggests a name from the profile and API', () {
    expect(
      suggestName(
        const AvdProfile(id: 'pixel_9', name: 'Pixel 9 (Google)'),
        36,
      ),
      'Pixel 9 API 36',
    );
  });

  test('rejects names avdmanager cannot take', () {
    final c = CreateDeviceController.forCreate()..setName('Pixel 9');
    expect(c.nameError, isNotNull);
    c.setName('ZZ_UI');
    expect(c.nameError, isNull);
  });

  test('loadCatalogs fills profiles and tags', () async {
    final c = controller(
      EmuBridge(
        emuPath: 'emu',
        runner: FakeRunner({'avd profiles': _profiles, 'avd tags': _tags}),
      ),
    );
    await c.loadCatalogs();
    expect(c.profiles.single.name, 'Pixel 9 (Google)');
    c.setProfile(c.profiles.single);
    await c.loadTags(36);
    expect(c.tags.single.installed, isTrue);
  });

  test('android submit sends every chosen field', () async {
    final runner = FakeRunner({
      'avd profiles': _profiles,
      'avd tags': _tags,
      'avd create': '{"ok":true,"data":{"name":"ZZ_UI","path":"/avd/ZZ_UI.avd","config":{}},"error":null}',
    });
    final c = controller(EmuBridge(emuPath: 'emu', runner: runner));
    await c.loadCatalogs();
    c.setProfile(c.profiles.single);
    await c.loadTags(36);
    c
      ..setApi(36)
      ..setTag(c.tags.single)
      ..setName('ZZ_UI')
      ..setRam(2048)
      ..setStorage('8G');
    expect(c.canSubmit, isTrue);

    await c.submit();

    expect(c.createdName, 'ZZ_UI');
    final create = runner.calls.firstWhere((c) => c.contains('create'));
    expect(create, containsAll(['--api', '36', '--tag', 'google_apis_playstore', '--abi', 'arm64-v8a', '--ram', '2048', '--storage', '8G']));
  });

  test('edit submit only sends the editable fields', () async {
    final runner = FakeRunner({
      'avd update': '{"ok":true,"data":{"name":"ZZ_Test","changed":["hw.ramSize"]},"error":null}',
    });
    final c = CreateDeviceController.forEdit(
      const AvdConfig(
        name: 'ZZ_Test',
        ram: 2048,
        api: 36,
        tag: 'google_apis_playstore',
      ),
      bridge: EmuBridge(emuPath: 'emu', runner: runner),
    )..setRam(4096);
    await c.submit();

    final update = runner.calls.single;
    expect(update, containsAll(['avd', 'update', '--name', 'ZZ_Test', '--ram', '4096']));
    expect(update, isNot(contains('--tag')));
  });

  test('ios submit creates a simulator', () async {
    final runner = FakeRunner({
      'ios device-types': _deviceTypes,
      'ios runtimes': _runtimes,
      'ios create': '{"ok":true,"data":{"udid":"U1","name":"ZZ_iOS"},"error":null}',
    });
    final c = controller(EmuBridge(emuPath: 'emu', runner: runner));
    await c.loadCatalogs();
    c.setPlatform(FormPlatform.ios);
    c.setIosDeviceType(c.iosDeviceTypes.single);
    c.setIosRuntime(c.iosRuntimes.single);
    c.setName('ZZ_iOS');
    expect(c.canSubmit, isTrue);

    await c.submit();

    expect(c.createdName, 'ZZ_iOS');
    expect(runner.calls.last, contains('create'));
  });

  test('a bridge error becomes a message with its hint', () async {
    final runner = FakeRunner({
      'avd profiles': _profiles,
      'avd tags': _tags,
      'avd create': '{"ok":false,"data":null,"error":{"code":"image_missing","message":"no image","hint":"install it"}}',
    });
    final c = controller(EmuBridge(emuPath: 'emu', runner: runner));
    await c.loadCatalogs();
    c.setProfile(c.profiles.single);
    await c.loadTags(36);
    c
      ..setApi(36)
      ..setTag(c.tags.single)
      ..setName('ZZ_UI');

    await c.submit();

    expect(c.createdName, isNull);
    expect(c.error, contains('no image'));
    expect(c.error, contains('install it'));
  });

  test('a thrown EmuException is stored, not rethrown', () async {
    final c = controller(
      EmuBridge(
        emuPath: 'emu',
        runner: FakeRunner({
          'avd profiles': _profiles,
          'avd tags': _tags,
          'avd create': '{"ok":false,"data":null,"error":{"code":"name_exists","message":"taken","hint":null}}',
        }),
      ),
    );
    await c.loadCatalogs();
    c.setProfile(c.profiles.single);
    await c.loadTags(36);
    c
      ..setApi(36)
      ..setTag(c.tags.single)
      ..setName('ZZ_UI');

    await expectLater(c.submit(), completes);
    expect(c.error, contains('taken'));
    expect(c.errorCode, 'name_exists');
  });
}
