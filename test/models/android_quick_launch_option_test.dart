import 'package:simutil/models/android_quick_launch_option.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidQuickLaunchOption', () {
    test('is enum', () {
      final normalOption = AndroidQuickLaunchOption.normal;
      expect(normalOption, isA<Enum>());
    });

    test('returns correct label', () {
      final normalOption = AndroidQuickLaunchOption.normal;
      expect(normalOption.label, 'Normal');
    });

    test('returns args is a list and correct args', () {
      final coldBootOption = AndroidQuickLaunchOption.coldBoot;

      expect(coldBootOption.args, isA<List<String>>());
      expect(coldBootOption.args, ['-no-snapshot-load']);
    });
  });
}
