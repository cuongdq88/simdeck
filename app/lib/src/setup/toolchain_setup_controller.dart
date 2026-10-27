import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/ui/runtimes/runtime_manager_controller.dart';

/// Runs a host command and streams its output lines (Homebrew).
abstract interface class SetupCommandRunner {
  Future<void> run(
    String exe,
    List<String> args,
    void Function(String line) onLine,
  );
}

class IoSetupCommandRunner implements SetupCommandRunner {
  const IoSetupCommandRunner();

  @override
  Future<void> run(
    String exe,
    List<String> args,
    void Function(String line) onLine,
  ) async {
    final process = await Process.start(exe, args);
    await for (final line
        in process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      onLine(line);
    }
    final code = await process.exitCode;
    if (code != 0) {
      throw ProcessException(exe, args, 'exit $code', code);
    }
  }
}

enum SetupStepKind { brew, sdkPackage }

/// One missing piece and how it gets installed.
class SetupStep {
  const SetupStep({required this.label, required this.kind, required this.id});

  final String label;
  final SetupStepKind kind;

  /// Homebrew cask or sdkmanager package id.
  final String id;
}

/// Installs what the app needs on a machine without Android Studio: the
/// command-line tools through Homebrew, then the `emulator` and
/// `platform-tools` SDK packages (spec §12.1, first-run setup).
class ToolchainSetupController extends ChangeNotifier {
  ToolchainSetupController({
    required this.report,
    required Future<EnvironmentReport> Function() check,
    required this.api,
    required this.runner,
    this.brewPath = 'brew',
  }) : _check = check,
       steps = _plan(report);

  static const cask = 'android-commandlinetools';

  static List<SetupStep> _plan(EnvironmentReport report) => [
    if (report.missing.contains('cmdline-tools'))
      const SetupStep(
        label: 'Android command-line tools',
        kind: SetupStepKind.brew,
        id: cask,
      ),
    if (report.missing.contains('platform-tools'))
      const SetupStep(
        label: 'Platform tools (adb)',
        kind: SetupStepKind.sdkPackage,
        id: 'platform-tools',
      ),
    if (report.missing.contains('emulator'))
      const SetupStep(
        label: 'Android emulator',
        kind: SetupStepKind.sdkPackage,
        id: 'emulator',
      ),
  ];

  final Future<EnvironmentReport> Function() _check;
  final RuntimeApi api;
  final SetupCommandRunner runner;
  final String brewPath;

  EnvironmentReport report;
  final List<SetupStep> steps;
  bool running = false;
  int progress = 0;
  String? currentStep;
  String? error;
  String? errorCode;

  bool get isReady => report.ready;

  /// Runs every planned step in order; returns whether the toolchain ends
  /// usable. Errors are stored in [error], never thrown at the UI.
  Future<bool> run() async {
    running = true;
    error = null;
    errorCode = null;
    notifyListeners();
    try {
      for (final step in steps) {
        currentStep = step.label;
        progress = 0;
        notifyListeners();
        switch (step.kind) {
          case SetupStepKind.brew:
            await runner.run(brewPath, [
              'install',
              '--cask',
              step.id,
            ], (line) {
              currentStep = line.trim().isEmpty ? step.label : line.trim();
              notifyListeners();
            });
          case SetupStepKind.sdkPackage:
            await for (final event in api.install(step.id)) {
              progress = event.percent;
              if (event.message.isNotEmpty) currentStep = event.message;
              notifyListeners();
            }
        }
      }
      report = await _check();
    } on ProcessException catch (e) {
      // Starting the brew binary is what fails on stock macOS.
      final missingBrew = e.executable == brewPath;
      errorCode = missingBrew ? 'brew_missing' : 'tool_failed';
      error = missingBrew
          ? 'Homebrew is required to install the Android SDK. Install it from '
                'https://brew.sh, then run the setup again.'
          : '${e.message}: ${e.errorCode}';
    } on EmuException catch (e) {
      errorCode = e.code;
      error = e.hint ?? e.message;
    } finally {
      running = false;
      currentStep = null;
      notifyListeners();
    }
    return report.ready;
  }
}
