import 'package:simutil_adb/src/emulator/emulator_grpc_session.dart';
import 'package:test/test.dart';

void main() {
  test('a guest that has not drawn yet is not a failure', () {
    expect(
      waitingForFirstFrame('The guest has not posted new frame yet.'),
      isTrue,
    );
  });

  test('other gRPC errors still fail the session', () {
    expect(waitingForFirstFrame('UNAVAILABLE: closed'), isFalse);
    expect(waitingForFirstFrame(''), isFalse);
  });
}
