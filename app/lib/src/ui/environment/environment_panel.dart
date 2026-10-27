import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_exception.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/setup/toolchain_setup_controller.dart';
import 'package:simutil_app/src/update/app_update_cubit.dart';
import 'package:simutil_app/src/ui/design/design.dart';
import 'package:simutil_app/src/ui/runtimes/runtime_manager_controller.dart';

/// Opens the Environment panel: SDK path, tool versions, Xcode, licenses
/// and free space, copyable for a bug report (spec §9.5).
Future<void> showEnvironmentPanel(BuildContext context, EmuBridge bridge) =>
    showDialog<void>(
      context: context,
      builder: (context) => EnvironmentPanel(bridge: bridge),
    );

class EnvironmentPanel extends StatefulWidget {
  const EnvironmentPanel({super.key, required this.bridge});

  final EmuBridge bridge;

  @override
  State<EnvironmentPanel> createState() => _EnvironmentPanelState();
}

class _EnvironmentPanelState extends State<EnvironmentPanel> {
  late Future<EnvironmentReport> _report = widget.bridge.envCheck();
  final _version = getAppVersion();
  ToolchainSetupController? _setup;

  void _startSetup(EnvironmentReport report) {
    final controller = ToolchainSetupController(
      report: report,
      check: widget.bridge.envCheck,
      api: EmuRuntimeApi(widget.bridge),
      runner: const IoSetupCommandRunner(),
    )..addListener(_rebuild);
    setState(() => _setup = controller);
    unawaited(
      controller.run().then((ready) {
        if (!mounted) return;
        if (ready) setState(() => _report = widget.bridge.envCheck());
      }),
    );
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _setup?.removeListener(_rebuild);
    super.dispose();
  }

  Widget _missingBanner(SimuTokens t, EnvironmentReport report) {
    final setup = _setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.triangleAlert, size: 14, color: t.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Missing: ${report.missing.join(', ')}',
                style: t.body.copyWith(color: t.warning),
              ),
            ),
            SimuButton(
              label: setup?.running == true
                  ? 'Installing…'
                  : 'Set up toolchain',
              primary: true,
              onPressed: setup?.running == true
                  ? null
                  : () => _startSetup(report),
            ),
          ],
        ),
        if (setup != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: setup.progress / 100),
          const SizedBox(height: 4),
          Text(setup.currentStep ?? 'Preparing…', style: t.caption),
        ],
        if (setup?.error case final error?) ...[
          const SizedBox(height: 8),
          Text(error, style: t.body.copyWith(color: t.danger)),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SimuPanel(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<EnvironmentReport>(
            future: _report,
            builder: (context, snapshot) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.stethoscope, size: 16, color: t.accent),
                      const SizedBox(width: 8),
                      Text('Environment', style: t.title),
                      const SizedBox(width: 8),
                      FutureBuilder<String>(
                        future: _version,
                        builder: (context, snapshot) => Text(
                          'SimDeck ${snapshot.data ?? ''}',
                          style: t.caption,
                        ),
                      ),
                      const Spacer(),
                      SimuIconButton(
                        icon: LucideIcons.copy,
                        tooltip: 'Copy the report',
                        onPressed: snapshot.hasData
                            ? () => Clipboard.setData(
                                ClipboardData(
                                  text: _asText(snapshot.requireData),
                                ),
                              )
                            : null,
                      ),
                      SimuIconButton(
                        icon: LucideIcons.x,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.error case final error?)
                    ..._errorSection(t, error)
                  else if (!snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: SimuSpinner()),
                    )
                  else ...[
                    if (!snapshot.requireData.ready)
                      _missingBanner(t, snapshot.requireData),
                    ..._rows(t, snapshot.requireData),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The helper could not even answer: show why, and still offer the setup
  /// that installs the whole toolchain.
  List<Widget> _errorSection(SimuTokens t, Object error) {
    final message = error is EmuException
        ? error.hint == null
              ? error.message
              : '${error.message} — ${error.hint}'
        : '$error';
    final canSetup = error is! EmuException ||
        error.code == 'sdk_not_found' ||
        error.code == 'tool_missing';
    return [
      Text(message, style: t.body.copyWith(color: t.danger)),
      if (canSetup) ...[
        const SizedBox(height: 10),
        if (_setup == null)
          Align(
            alignment: Alignment.centerLeft,
            child: SimuButton(
              label: 'Set up toolchain',
              primary: true,
              onPressed: () => _startSetup(_toolchainReport()),
            ),
          )
        else ...[
          LinearProgressIndicator(value: _setup!.progress / 100),
          const SizedBox(height: 4),
          Text(_setup!.currentStep ?? 'Preparing…', style: t.caption),
          if (_setup!.error case final setupError?)
            Text(setupError, style: t.body.copyWith(color: t.danger)),
        ],
      ],
    ];
  }

  /// What a machine with nothing installed needs, for the setup button that
  /// appears when the helper itself cannot start.
  EnvironmentReport _toolchainReport() => const EnvironmentReport(
    sdkPath: '',
    avdHome: '',
    adb: null,
    emulator: null,
    avdmanager: null,
    sdkmanager: null,
    xcode: null,
    licensesAccepted: false,
    ready: false,
    missing: ['cmdline-tools', 'platform-tools', 'emulator'],
  );

  List<Widget> _rows(SimuTokens t, EnvironmentReport report) {
    final rows = <String, String>{
      'Android SDK': report.sdkPath,
      'AVD home': report.avdHome,
      'adb': report.adb ?? 'not found',
      'emulator': report.emulator ?? 'not found',
      'avdmanager': report.avdmanager ?? 'not found',
      'sdkmanager': report.sdkmanager ?? 'not found',
      'Xcode': report.xcode ?? 'not found',
      'SDK licenses': report.licensesAccepted ? 'accepted' : 'not accepted',
      'Free disk': report.diskFreeLabel,
    };
    return [
      for (final entry in rows.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(entry.key, style: t.overline),
              ),
              Expanded(
                child: SelectableText(
                  entry.value,
                  style: t.mono.copyWith(color: t.text),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  String _asText(EnvironmentReport report) => [
    'Android SDK: ${report.sdkPath}',
    'AVD home: ${report.avdHome}',
    'adb: ${report.adb ?? 'not found'}',
    'emulator: ${report.emulator ?? 'not found'}',
    'avdmanager: ${report.avdmanager ?? 'not found'}',
    'sdkmanager: ${report.sdkmanager ?? 'not found'}',
    'Xcode: ${report.xcode ?? 'not found'}',
    'SDK licenses: ${report.licensesAccepted ? 'accepted' : 'not accepted'}',
    'Free disk: ${report.diskFreeLabel}',
  ].join('\n');
}
