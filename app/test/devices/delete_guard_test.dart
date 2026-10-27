import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_shared/simutil_shared.dart';
import 'package:simutil_app/src/devices/devices_cubit.dart';
import 'package:simutil_core/simutil_core.dart';
import 'package:simutil_core/testing.dart';

void main() {
  Device emulator(String name) => Device.android(
    id: name,
    name: name,
    state: DeviceState.shutdown,
    type: DeviceType.simulator,
  );

  test('a shared AVD directory blocks delete before any adb call', () async {
    final android = FakeDeviceService();
    final cubit = DevicesCubit(
      android: android,
      ios: FakeDeviceService(),
      loadIos: false,
      guard: DeletionGuard.fromFiles(const [
        IniFile('E1', '/avd/Pixel_9_Pro_XL.avd'),
        IniFile('Pixel_9_Pro_XL', '/avd/Pixel_9_Pro_XL.avd'),
      ]),
    );
    final notices = <DeviceNotice>[];
    cubit.notices.listen(notices.add);

    await cubit.delete(emulator('E1'));
    await Future<void>.delayed(Duration.zero);

    expect(android.deleted, isEmpty);
    expect(notices.last.kind, DeviceNoticeKind.error);
    expect(notices.last.text, contains('Pixel_9_Pro_XL'));
    await cubit.close();
  });

  test('a shared AVD directory blocks wipe too', () async {
    final android = FakeDeviceService();
    final cubit = DevicesCubit(
      android: android,
      ios: FakeDeviceService(),
      loadIos: false,
      guard: DeletionGuard.fromFiles(const [
        IniFile('E1', '/avd/Pixel_9_Pro_XL.avd'),
        IniFile('Pixel_9_Pro_XL', '/avd/Pixel_9_Pro_XL.avd'),
      ]),
    );

    await cubit.wipeData(emulator('E1'));

    expect(android.wiped, isEmpty);
    await cubit.close();
  });

  test('a lone AVD still deletes', () async {
    final android = FakeDeviceService();
    final cubit = DevicesCubit(
      android: android,
      ios: FakeDeviceService(),
      loadIos: false,
      guard: DeletionGuard.fromFiles(const [IniFile('ZZ_Test', '/avd/ZZ.avd')]),
    );

    await cubit.delete(emulator('ZZ_Test'));

    expect(android.deleted, ['ZZ_Test']);
    await cubit.close();
  });

  test('an iOS simulator is never guarded', () async {
    final ios = FakeDeviceService();
    final cubit = DevicesCubit(
      android: FakeDeviceService(),
      ios: ios,
      loadIos: true,
      guard: DeletionGuard.fromFiles(const []),
    );

    await cubit.delete(
      Device.ios(
        id: 'u1',
        name: 'iPhone',
        state: DeviceState.shutdown,
        type: DeviceType.simulator,
      ),
    );

    expect(ios.deleted, ['u1']);
    await cubit.close();
  });
}
