import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/ui/create/create_device_controller.dart';
import 'package:simutil_app/src/ui/create/create_device_sheet.dart';
import 'package:simutil_app/src/ui/design/design.dart';

class _Runner implements ProcessRunner {
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add(args);
    return ProcessResult(
      0,
      0,
      '{"ok":true,"data":{"name":"ZZ_Test","changed":["hw.ramSize"]},"error":null}',
      '',
    );
  }

  @override
  Stream<String> stream(String exe, List<String> args) => const Stream.empty();
}

Widget _wrap(Widget child) => MaterialApp(
  theme: simuTheme(Brightness.dark),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the sidebar picks the platform, there is no tab switch', (
    tester,
  ) async {
    final controller = CreateDeviceController.forCreate(
      platform: FormPlatform.ios,
      bridge: EmuBridge(emuPath: 'emu', runner: _Runner()),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wrap(CreateDeviceSheet(controller: controller)),
    );
    await tester.pump();

    expect(find.text('New iOS simulator'), findsOneWidget);
    expect(find.text('Device type'), findsOneWidget);
    expect(find.text('Android'), findsNothing);
    expect(find.byType(SegmentedButton<FormPlatform>), findsNothing);
  });

  testWidgets('edit mode hides the locked image fields', (tester) async {
    final controller = CreateDeviceController.forEdit(
      const AvdConfig(
        name: 'ZZ_Test',
        ram: 2048,
        api: 36,
        tag: 'google_apis_playstore',
      ),
      bridge: EmuBridge(emuPath: 'emu', runner: _Runner()),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(CreateDeviceSheet(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Edit device'), findsOneWidget);
    expect(
      find.text('The name cannot change; create a new device for another name.'),
      findsOneWidget,
    );
    expect(find.text('Hardware profile'), findsNothing);
    expect(find.text('API level (installed images)'), findsNothing);
    expect(find.text('RAM (MB)'), findsOneWidget);
  });

  testWidgets('Update sends only the editable fields', (tester) async {
    final runner = _Runner();
    final controller = CreateDeviceController.forEdit(
      const AvdConfig(
        name: 'ZZ_Test',
        ram: 2048,
        api: 36,
        tag: 'google_apis_playstore',
      ),
      bridge: EmuBridge(emuPath: 'emu', runner: runner),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(CreateDeviceSheet(controller: controller)));
    await tester.pumpAndSettle();

    // The name field is read-only in Edit, so RAM is the second field.
    await tester.enterText(find.byType(TextField).at(1), '4096');
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(runner.calls.single, containsAll(['avd', 'update', '--ram', '4096']));
    expect(runner.calls.single, isNot(contains('--tag')));
  });
}
