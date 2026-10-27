import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/ui/design/design.dart';

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
  late final Future<EnvironmentReport> _report = widget.bridge.envCheck();

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
                  if (snapshot.hasError)
                    Text(
                      '${snapshot.error}',
                      style: t.body.copyWith(color: t.danger),
                    )
                  else if (!snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: SimuSpinner()),
                    )
                  else
                    ..._rows(t, snapshot.requireData),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

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
