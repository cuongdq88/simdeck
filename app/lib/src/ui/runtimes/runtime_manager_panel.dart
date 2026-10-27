import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/ui/design/design.dart';
import 'package:simutil_app/src/ui/runtimes/runtime_manager_controller.dart';

/// Opens the SDK Manager: installed and downloadable SDK packages (system
/// images), progress, licenses (spec §9.3).
Future<void> showRuntimeManager(BuildContext context, RuntimeManagerController c) =>
    showDialog<void>(
      context: context,
      builder: (context) => RuntimeManagerPanel(controller: c),
    );

class RuntimeManagerPanel extends StatefulWidget {
  const RuntimeManagerPanel({super.key, required this.controller});

  final RuntimeManagerController controller;

  @override
  State<RuntimeManagerPanel> createState() => _RuntimeManagerPanelState();
}

class _RuntimeManagerPanelState extends State<RuntimeManagerPanel> {
  late final RuntimeManagerController _c = widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_rebuild);
    _c.load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    // Grouped like sdkmanager: one block per API, newest first.
    final groups = {
      for (final entry in _c.groupedByApi.entries)
        entry.key: [
          for (final image in entry.value)
            if (_c.installing == null || _c.installing == image.package) image,
        ],
    }..removeWhere((_, images) => images.isEmpty);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: SimuPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.hardDriveDownload, size: 16, color: t.accent),
                  const SizedBox(width: 8),
                  Text('SDK Manager', style: t.title),
                  const Spacer(),
                  SimuIconButton(
                    icon: LucideIcons.refreshCw,
                    tooltip: 'Refresh',
                    onPressed: _c.load,
                  ),
                  SimuIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (_c.licensesRequired) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(LucideIcons.triangleAlert, size: 14, color: t.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'The SDK licenses are not accepted yet.',
                        style: t.body.copyWith(color: t.warning),
                      ),
                    ),
                    SimuButton(
                      label: 'Accept licenses',
                      onPressed: _c.acceptLicenses,
                    ),
                  ],
                ),
              ],
              if (_c.installing case final installing?) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _c.progress / 100),
                const SizedBox(height: 4),
                Text(
                  _c.progressMessage.isEmpty
                      ? 'Installing $installing…'
                      : '${_c.progressMessage} (${_c.progress}%)',
                  style: t.caption,
                ),
              ],
              if (_c.error case final error?) ...[
                const SizedBox(height: 10),
                Text(error, style: t.body.copyWith(color: t.danger)),
              ],
              const SizedBox(height: 10),
              if (_c.loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: SimuSpinner()),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                          child: Row(
                            children: [
                              Text('API ${entry.key}', style: t.overline),
                              const SizedBox(width: 6),
                              Text(
                                '${entry.value.length}',
                                style: t.mono.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        for (final image in entry.value)
                          _ImageRow(
                            image: image,
                            busy: _c.installing != null,
                            onInstall: () => _c.install(image.package),
                            onUninstall: () => _c.uninstall(image.package),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageRow extends StatelessWidget {
  const _ImageRow({
    required this.image,
    required this.busy,
    required this.onInstall,
    required this.onUninstall,
  });

  final ImagePackage image;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    final detail = [
      'API ${image.api}',
      image.tag,
      image.abi,
      if (image.sizeLabel.isNotEmpty) image.sizeLabel,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            image.installed ? LucideIcons.circleCheck : LucideIcons.circleDashed,
            size: 14,
            color: image.installed ? t.success : t.textFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(image.package, style: t.mono.copyWith(color: t.text)),
                Text(detail, style: t.caption),
              ],
            ),
          ),
          if (image.installed)
            SimuButton(
              label: 'Uninstall',
              onPressed: busy ? null : onUninstall,
            )
          else
            SimuButton(
              label: 'Install',
              primary: true,
              onPressed: busy ? null : onInstall,
            ),
        ],
      ),
    );
  }
}
