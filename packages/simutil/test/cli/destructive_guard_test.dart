import 'package:args/command_runner.dart';
import 'package:simutil_shared/simutil_shared.dart';
import 'package:simutil/src/cli/cli_device_services.dart';
import 'package:simutil_core/simutil_core.dart';
import 'package:simutil_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('delete refuses two .ini files sharing one AVD directory', () async {
    final service = FakeDeviceService();
    final services = CliDeviceServices(
      services: {DeviceOs.android: service},
      guard: () => DeletionGuard.fromFiles(const [
        IniFile('E1', '/avd/Pixel_9_Pro_XL.avd'),
        IniFile('Pixel_9_Pro_XL', '/avd/Pixel_9_Pro_XL.avd'),
      ]),
    );

    await expectLater(
      services.deleteDevice(
        Device.android(
          id: 'E1',
          name: 'E1',
          state: DeviceState.shutdown,
          type: DeviceType.simulator,
        ),
      ),
      throwsA(
        isA<UsageException>().having(
          (e) => e.message,
          'message',
          contains('Pixel_9_Pro_XL'),
        ),
      ),
    );
    expect(service.deleted, isEmpty);
  });
}
