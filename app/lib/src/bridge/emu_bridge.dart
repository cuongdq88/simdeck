import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';

/// Runs the `emu` helper: one process per call, stdio captured.
abstract class ProcessRunner {
  Future<ProcessResult> run(String exe, List<String> args);

  /// stdout of `exe` line by line, for NDJSON progress streams.
  Stream<String> stream(String exe, List<String> args);
}

class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<ProcessResult> run(String exe, List<String> args) =>
      Process.run(exe, args);

  @override
  Stream<String> stream(String exe, List<String> args) async* {
    final process = await Process.start(exe, args);
    // License prompts come on stdin; answer them the same way the CLI does.
    process.stdin.write('y\n');
    await process.stdin.flush();
    await for (final line
        in process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      yield line;
    }
    await process.stderr.drain<void>();
    final code = await process.exitCode;
    if (code != 0) {
      throw EmuException('tool_failed', 'emu exited with $code');
    }
  }
}

/// Client for the helper's JSON CLI (spec §8).
class EmuBridge {
  EmuBridge({required this.emuPath, ProcessRunner? runner})
    : _runner = runner ?? const IoProcessRunner();

  /// Path of the helper: inside the app bundle in a release build, a dev
  /// checkout otherwise.
  static String resolveEmuPath() {
    final bundled = File(
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/emu',
    );
    if (bundled.existsSync()) return bundled.path;
    final local = File('${Directory.current.path}/build/emu-universal');
    if (local.existsSync()) return local.path;
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Workspace/emu/target/debug/emu';
  }

  final String emuPath;
  final ProcessRunner _runner;

  static const _timeout = Duration(seconds: 30);

  /// Runs `args --json`, decodes the envelope and hands `data` to [parse].
  Future<T> run<T>(List<String> args, T Function(Object? json) parse) async {
    final ProcessResult result;
    try {
      result = await _runner
          .run(emuPath, ['--json', ...args])
          .timeout(_timeout);
    } on TimeoutException {
      throw const EmuException('tool_failed', 'The emulator helper timed out');
    }
    final envelope = _lastJsonObject(result.stdout as String);
    if (envelope == null) {
      final message = (result.stdout as String).trim().isEmpty
          ? (result.stderr as String).trim()
          : (result.stdout as String).trim();
      throw EmuException(
        'tool_failed',
        message.isEmpty ? 'The emulator helper printed no JSON' : message,
      );
    }
    if (result.exitCode == 0 && envelope['ok'] == true) {
      return parse(envelope['data']);
    }
    final error = envelope['error'] as Map?;
    throw EmuException(
      error?['code'] as String? ?? 'tool_failed',
      error?['message'] as String? ?? 'The emulator helper failed',
      hint: error?['hint'] as String?,
    );
  }

  /// Convenience wrappers for the calls the UI makes.
  Future<List<AvdProfile>> avdProfiles() => run(
    ['avd', 'profiles'],
    (json) => [
      for (final row in json as List) AvdProfile.fromJson(row),
    ],
  );

  Future<List<AvdTag>> avdTags(int api) => run(
    ['avd', 'tags', '--api', '$api'],
    (json) => [
      for (final row in json as List) AvdTag.fromJson(row),
    ],
  );

  Future<List<IosDeviceType>> iosDeviceTypes() => run(
    ['ios', 'device-types'],
    (json) => [
      for (final row in json as List) IosDeviceType.fromJson(row),
    ],
  );

  Future<List<IosRuntime>> iosRuntimes() => run(
    ['ios', 'runtimes'],
    (json) => [
      for (final row in json as List) IosRuntime.fromJson(row),
    ],
  );

  Future<EnvironmentReport> envCheck() =>
      run(['env', 'check'], EnvironmentReport.fromJson);

  Future<AvdConfig> avdShow(String name) =>
      run(['avd', 'show', '--name', name], AvdConfig.fromShow);

  Future<List<ImagePackage>> images({String platform = 'android'}) => run(
    ['images', 'list', '--platform', platform],
    (json) => [
      for (final row in json as List) ImagePackage.fromJson(row),
    ],
  );

  /// Streams install progress; the stream closes on success and throws an
  /// [EmuException] on the final error line.
  Stream<InstallProgress> install(String package) async* {
    final lines = _runner.stream(emuPath, [
      '--json',
      'images',
      'install',
      '--package',
      package,
    ]);
    await for (final line in lines) {
      final event = _decode(line);
      if (event == null) continue;
      switch (event['event']) {
        case 'progress':
          yield InstallProgress(
            percent: (event['percent'] as num?)?.toInt() ?? 0,
            message: event['message'] as String? ?? '',
          );
        case 'done':
          if (event['ok'] != true) {
            final error = event['error'] as Map?;
            throw EmuException(
              error?['code'] as String? ?? 'tool_failed',
              error?['message'] as String? ?? 'Install failed',
              hint: error?['hint'] as String?,
            );
          }
          return;
      }
    }
  }

  /// Accepts SDK licenses, streaming progress like [install].
  Stream<InstallProgress> acceptLicenses() async* {
    final lines = _runner.stream(emuPath, [
      '--json',
      'licenses',
      'accept',
    ]);
    await for (final line in lines) {
      final event = _decode(line);
      if (event == null) continue;
      if (event['event'] == 'progress') {
        yield InstallProgress(
          percent: (event['percent'] as num?)?.toInt() ?? 0,
          message: event['message'] as String? ?? '',
        );
      } else if (event['event'] == 'done' && event['ok'] != true) {
        final error = event['error'] as Map?;
        throw EmuException(
          error?['code'] as String? ?? 'tool_failed',
          error?['message'] as String? ?? 'License acceptance failed',
          hint: error?['hint'] as String?,
        );
      }
    }
  }

  static Map? _decode(String line) {
    try {
      final value = jsonDecode(line);
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// The envelope is the last JSON object on stdout; earlier lines may be
  /// tool noise.
  static Map? _lastJsonObject(String stdout) {
    for (final line in stdout.trimRight().split('\n').reversed) {
      final value = _decode(line.trim());
      if (value != null) return value;
    }
    return null;
  }
}
