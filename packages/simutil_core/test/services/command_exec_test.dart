import 'dart:async';
import 'dart:io';

import 'package:simutil_core/src/command_exec.dart';
import 'package:test/test.dart';

void main() {
  group('CommandResult', () {
    test('success is true only for exit code 0', () {
      expect(
        const CommandResult(stdout: '', stderr: '', exitCode: 0).success,
        isTrue,
      );
      expect(
        const CommandResult(stdout: '', stderr: '', exitCode: 1).success,
        isFalse,
      );
    });
  });

  group('CommandExec()', () {
    test('runs a real process and captures exit code 0', () async {
      final exec = CommandExec();

      final result = await exec.run(
        Platform.resolvedExecutable,
        arguments: ['--version'],
      );

      expect(result.exitCode, 0);
      expect(result.success, isTrue);
    });

    test('reports non-zero exit for invalid arguments', () async {
      final exec = CommandExec();

      final result = await exec.run(
        Platform.resolvedExecutable,
        arguments: ['--definitely-not-a-flag'],
      );

      expect(result.success, isFalse);
    });

    test('closes stdin so commands reading it see EOF', () async {
      final result = await CommandExec().run(
        'cat',
        timeout: const Duration(seconds: 5),
      );

      expect(result.success, isTrue);
    }, testOn: '!windows');

    test('kills the process and throws on timeout', () async {
      final exec = CommandExec();

      await expectLater(
        exec.run(
          'sleep',
          arguments: ['5'],
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
    }, testOn: '!windows');
  });
}
