import 'package:simutil/models/device.dart';

abstract class DeviceService {
  Future<bool> isAvailable();

  Future<List<Device>> listDevices();

  Future<void> launchDevice({
    required String deviceId,
    List<String> additionalArgs = const [],
  });
}
