import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/setup/toolchain_setup_controller.dart';
import 'package:simutil_app/src/ui/runtimes/runtime_manager_controller.dart';

class _Api implements RuntimeApi {
  _Api({this.installError});

  final EmuException? installError;
  final installed = <String>[];

  @override
  Future<List<ImagePackage>> images({String platform = 'android'}) async => [];

  @override
  Stream<InstallProgress> install(String package) async* {
    installed.add(package);
    if (installError case final error?) throw error;
    yield const InstallProgress(percent: 100, message: 'done');
  }

  @override
  Stream<InstallProgress> acceptLicenses() async* {}

  @override
  Future<void> uninstall(String package) async {}
}

class _Brew implements SetupCommandRunner {
  _Brew({this.error});

  final Object? error;
  final calls = <List<String>>[];

  @override
  Future<void> run(
    String exe,
    List<String> args,
    void Function(String line) onLine,
  ) async {
    calls.add([exe, ...args]);
    if (error != null) throw error!;
    onLine('installing…');
  }
}

EnvironmentReport _report(List<String> missing) => EnvironmentReport(
  sdkPath: '/sdk',
  avdHome: '/avd',
  adb: missing.contains('platform-tools') ? null : 'adb 1',
  emulator: missing.contains('emulator') ? null : 'emulator 1',
  avdmanager: missing.contains('cmdline-tools') ? null : '23',
  sdkmanager: missing.contains('cmdline-tools') ? null : '1',
  xcode: 'Xcode 27.1',
  licensesAccepted: true,
  ready: missing.isEmpty,
  missing: missing,
);

void main() {
  test('plans one step per missing tool, command-line tools through brew', () {
    final c = ToolchainSetupController(
      report: _report(['platform-tools', 'emulator', 'cmdline-tools']),
      check: () async => _report([]),
      api: _Api(),
      runner: _Brew(),
    );
    expect(c.steps.map((s) => s.label), [
      'Android command-line tools',
      'Platform tools (adb)',
      'Android emulator',
    ]);
    expect(c.steps.first.kind, SetupStepKind.brew);
  });

  test('a ready toolchain plans nothing', () {
    final c = ToolchainSetupController(
      report: _report([]),
      check: () async => _report([]),
      api: _Api(),
      runner: _Brew(),
    );
    expect(c.steps, isEmpty);
  });

  test('installs the missing packages and ends ready', () async {
    final api = _Api();
    final brew = _Brew();
    final c = ToolchainSetupController(
      report: _report(['platform-tools', 'emulator', 'cmdline-tools']),
      check: () async => _report([]),
      api: api,
      runner: brew,
    );

    expect(await c.run(), isTrue);

    expect(brew.calls.single, containsAll(['brew', 'install', '--cask']));
    expect(api.installed, ['platform-tools', 'emulator']);
    expect(c.error, isNull);
  });

  test('a missing Homebrew stops the setup with a hint', () async {
    final api = _Api();
    final c = ToolchainSetupController(
      report: _report(['cmdline-tools']),
      check: () async => _report(['cmdline-tools']),
      api: api,
      runner: _Brew(error: const ProcessException('brew', ['install'])),
    );

    expect(await c.run(), isFalse);

    expect(c.error, contains('Homebrew'));
    expect(api.installed, isEmpty);
  });

  test('a failed sdkmanager install surfaces its hint', () async {
    final c = ToolchainSetupController(
      report: _report(['emulator']),
      check: () async => _report(['emulator']),
      api: _Api(
        installError: const EmuException(
          'tool_missing',
          'sdkmanager not found',
          hint: 'Install the command-line tools first',
        ),
      ),
      runner: _Brew(),
    );

    expect(await c.run(), isFalse);
    expect(c.error, contains('Install the command-line tools first'));
  });
}
