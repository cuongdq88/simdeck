import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simutil_app/src/di.dart';
import 'package:simutil_app/src/settings/desktop_settings_store.dart';
import 'package:simutil_app/src/update/app_update_cubit.dart';
import 'package:simutil_core/simutil_core.dart';

void main() {
  test('update cubit is not created when updates are disabled', () async {
    final di = await buildDi(
      di: GetIt.asNewInstance(),
      env: const {'SIMDECK_NO_UPDATE': '1'},
      isolateRunner: IsolateRunner(),
      settingsStore: DesktopSettingsStore(),
    );
    expect(di.isRegistered<AppUpdateCubit>(), isFalse);
    await di.reset();
  });

  test('the release build define alone disables updates', () {
    expect(
      updatesEnabled(const {}, dartDefine: 'true'),
      isFalse,
    );
    expect(updatesEnabled(const {'SIMDECK_NO_UPDATE': '1'}), isFalse);
    expect(updatesEnabled(const {}), isTrue);
  });
}
