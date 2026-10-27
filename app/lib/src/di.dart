import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:simutil_shared/simutil_shared.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/logging/debug_log.dart';
import 'package:simutil_adb/simutil_adb.dart';
import 'package:simutil_app/src/devices/slim_mode_cubit.dart';
import 'package:simutil_app/src/recording/recording_lock.dart';
import 'package:simutil_app/src/devices/devices_cubit.dart';
import 'package:simutil_app/src/recording/grid_recorder.dart';
import 'package:simutil_app/src/recording/saved_recordings.dart';
import 'package:simutil_app/src/scenarios/scenario_runs_cubit.dart';
import 'package:simutil_app/src/settings/desktop_settings_store.dart';
import 'package:simutil_app/src/settings/device_settings_cubit.dart';
import 'package:simutil_app/src/settings/view_settings_cubit.dart';
import 'package:simutil_app/src/stream/streams_cubit.dart';
import 'package:simutil_app/src/stream/touch_marks.dart';
import 'package:simutil_app/src/update/app_installer.dart';
import 'package:simutil_app/src/update/app_update_cubit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:simutil_apple/simutil_apple.dart';
import 'package:simutil_core/simutil_core.dart';

/// App-wide service locator.
final getIt = GetIt.instance;

/// Whether this build may check for updates. A brew-managed app must never
/// update itself: brew's sha256 and the version in the app would drift
/// (spec §12.2). [env] is the process environment, [dartDefine] the
/// `--dart-define=SIMDECK_NO_UPDATE` value of a release build.
bool updatesEnabled(
  Map<String, String> env, {
  String dartDefine = const String.fromEnvironment('SIMDECK_NO_UPDATE'),
}) {
  // SimDeck ships through Homebrew and has no release feed of its own, so the
  // updater stays off unless a build opts in explicitly. Without this a dev
  // build offered SimUtil 0.5.0 from the upstream repository.
  if (dartDefine == 'true' || dartDefine == '1') return false;
  if (env['SIMDECK_NO_UPDATE'] == '1') return false;
  return env['SIMDECK_UPDATES'] == '1';
}

/// Starts the shell-command isolate and registers the device services plus
/// the app's cubits.
Future<void> configureDependencies() async {
  await buildDi();
}

/// The registration itself, with the process-wide pieces injectable so
/// tests can build a locator without touching the disk or an isolate.
Future<GetIt> buildDi({
  GetIt? di,
  Map<String, String> env = const {},
  String dartDefine = const String.fromEnvironment('SIMDECK_NO_UPDATE'),
  IsolateRunner? isolateRunner,
  DesktopSettingsStore? settingsStore,
}) async {
  final target = di ?? getIt;
  final runner = isolateRunner ?? IsolateRunner();
  if (isolateRunner == null) await runner.init();
  final debugLog = DebugLog();
  final exec = LoggingCommandExec(CommandExec.isolate(runner), debugLog);
  final store = settingsStore ?? DesktopSettingsStore();
  if (settingsStore == null) await store.load();

  target
    // First in, last disposed: cubits close before the final save is awaited.
    ..registerSingleton<DesktopSettingsStore>(
      store,
      dispose: (store) => store.flush(),
    )
    ..registerSingleton<DebugLog>(debugLog)
    ..registerSingleton<IsolateRunner>(
      runner,
      dispose: (runner) => runner.dispose(),
    )
    ..registerSingleton<CommandExec>(exec)
    ..registerLazySingleton<EmuBridge>(
      () => EmuBridge(emuPath: EmuBridge.resolveEmuPath()),
    )
    ..registerLazySingleton<DeletionGuard>(
      () => DeletionGuard.load(
        // Late lookup: the guard asks the cubit which AVDs are booted when it
        // is actually used, never at startup.
        runningAvdsLoader: () async => {
          for (final device in target<DevicesCubit>().stateValue.androidEmulators)
            if (device.state == DeviceState.booted) device.name,
        },
      ),
    )
    ..registerSingleton<AndroidDeviceService>(AndroidDeviceService(exec))
    ..registerLazySingleton<WifiDiscoveryService>(MdnsWifiDiscoveryService.new)
    ..registerLazySingleton<AdbWirelessPairing>(
      () => AdbWirelessPairing(
        target<AndroidDeviceService>(),
        target<WifiDiscoveryService>(),
      ),
    )
    ..registerSingleton<IOSDeviceService>(IOSDeviceService(exec))
    ..registerSingleton<IosAutomation>(IosAutomation(exec))
    ..registerSingleton<XcodeCacheService>(XcodeCacheService(exec))
    ..registerLazySingleton<DevicesCubit>(
      () => DevicesCubit(
        android: target<AndroidDeviceService>(),
        ios: target<IOSDeviceService>(),
        slim: _SimulatorSlimControl(SimulatorSlimmer(target<CommandExec>())),
        guard: target<DeletionGuard>(),
        // Late lookup: SlimModeCubit itself depends on DevicesCubit.
        slimOnLaunch: () => target<SlimModeCubit>().stateValue.enabled,
      ),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<DeviceSettingsCubit>(
      () => DeviceSettingsCubit(store: target<DesktopSettingsStore>()),
      dispose: (cubit) => cubit.close(),
    )
    ..registerSingleton<SavedRecordings>(
      SavedRecordings(exec),
      dispose: (saved) => saved.dispose(),
    )
    ..registerSingleton(RecordingLock())
    ..registerSingleton(TouchMarks(), dispose: (marks) => marks.dispose())
    ..registerLazySingleton<GridRecorderCubit>(
      () => GridRecorderCubit(
        onSaved: target<SavedRecordings>().add,
        recordingLock: target<RecordingLock>(),
      ),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<ScenarioRunsCubit>(
      ScenarioRunsCubit.new,
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<ViewSettingsCubit>(
      () => ViewSettingsCubit(store: target<DesktopSettingsStore>()),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<StreamsCubit>(
      () => StreamsCubit(
        defaultSessionFactory(
          exec: target<CommandExec>(),
          adbPath: () => target<AndroidDeviceService>().adbPath,
          settings: (device) => target<DeviceSettingsCubit>().of(device),
        ),
        onSaved: target<SavedRecordings>().add,
        recordingLock: target<RecordingLock>(),
      ),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<AppInstaller>(
      () => AppInstaller(exec, quit: quitApp),
    )
    ..registerLazySingleton<SlimModeCubit>(
      () => SlimModeCubit(
        devices: target<DevicesCubit>(),
        streams: target<StreamsCubit>(),
        store: target<DesktopSettingsStore>(),
      ),
      dispose: (cubit) => cubit.close(),
    );

  if (updatesEnabled(env, dartDefine: dartDefine)) {
    target.registerSingleton<AppUpdateCubit>(
      AppUpdateCubit(currentVersion: await getAppVersion()),
      dispose: (cubit) => cubit.close(),
    );
  }
  return target;
}

class _SimulatorSlimControl implements SlimControl {
  _SimulatorSlimControl(this._slimmer);

  final SimulatorSlimmer _slimmer;

  @override
  Future<bool> isSlim(String udid) => _slimmer.isSlim(udid);

  @override
  Future<void> setSlim(String udid, {required bool slim}) =>
      slim ? _slimmer.slim(udid) : _slimmer.unslim(udid);
}

/// Closes cubits and stops the shell-command isolate.
Future<void> disposeDependencies() => getIt.reset();

/// Releases streams and recordings, then closes the window and quits.
Future<void> quitApp() async {
  try {
    await disposeDependencies();
  } catch (e, s) {
    debugPrint('Dispose on quit failed: $e\n$s');
  } finally {
    await windowManager.destroy();
  }
}
