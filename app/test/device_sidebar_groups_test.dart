import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/devices/devices_state.dart';
import 'package:simutil_app/src/ui/devices/device_sidebar.dart';
import 'package:simutil_core/simutil_core.dart';

void main() {
  Device android(String name, DeviceState state) => Device.android(
    id: name,
    name: name,
    state: state,
    type: DeviceType.simulator,
  );

  Device iphone(String name, DeviceState state) => Device.ios(
    id: name,
    name: name,
    state: state,
    type: DeviceType.simulator,
  );

  test('runningDevices collects booted and booting devices from every list', () {
    final state = DevicesState(
      androidDevices: [
        Device.android(
          id: 'phone',
          name: 'phone',
          state: DeviceState.booted,
          type: DeviceType.physical,
        ),
      ],
      androidEmulators: [
        android('emulator-on', DeviceState.booted),
        android('emulator-off', DeviceState.shutdown),
      ],
      iosDevices: [
        Device.ios(
          id: 'iphone-usb',
          name: 'iphone-usb',
          state: DeviceState.booted,
          type: DeviceType.physical,
        ),
      ],
      iosSimulators: [
        iphone('sim-booting', DeviceState.booting),
        iphone('sim-off', DeviceState.shutdown),
      ],
    );

    expect(
      runningDevices(state).map((d) => d.name),
      ['phone', 'emulator-on', 'iphone-usb', 'sim-booting'],
    );
  });

  test('idleDevices drops what RUNNING already shows', () {
    final devices = [
      android('on', DeviceState.booted),
      android('off', DeviceState.shutdown),
      android('starting', DeviceState.booting),
    ];
    expect(idleDevices(devices).map((d) => d.name), ['off']);
  });
}
