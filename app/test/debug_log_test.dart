import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/logging/debug_log.dart';
import 'package:simutil_core/testing.dart';

void main() {
  test('logs commands while running and once done; keeps the newest', () async {
    final log = DebugLog();
    final exec = LoggingCommandExec(
      FakeCommandExec((_, _) => FakeCommandExec.ok()),
      log,
    );
    final run = exec.run('adb', arguments: ['devices']);
    expect(log.running.single.text, 'adb devices');
    await run;
    expect(log.running, isEmpty);
    expect(log.entries.single.text, startsWith('adb devices  → ok'));

    for (var i = 0; i < DebugLog.maxEntries + 5; i++) {
      log.add(DebugSource.mcp, '$i');
    }
    expect(log.entries.length, DebugLog.maxEntries);
    expect(log.entries.last.text, '${DebugLog.maxEntries + 4}');
  });
}
