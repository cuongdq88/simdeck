import 'package:simutil_adb/src/emulator/emulator_grpc_session.dart';
import 'package:simutil_core/simutil_core.dart';
import 'package:test/test.dart';

void main() {
  test('a guest that has not drawn yet is not a failure', () {
    expect(
      waitingForFirstFrame('The guest has not posted new frame yet.'),
      isTrue,
    );
  });

  test('nav buttons map to Android key codes', () {
    expect(emulatorKeyEventCode(DeviceButton.back), 4);
    expect(emulatorKeyEventCode(DeviceButton.home), 3);
    expect(emulatorKeyEventCode(DeviceButton.recents), 187);
    expect(emulatorKeyEventCode(DeviceButton.lock), 26);
  });

  test('other gRPC errors still fail the session', () {
    expect(waitingForFirstFrame('UNAVAILABLE: closed'), isFalse);
    expect(waitingForFirstFrame(''), isFalse);
  });
}
