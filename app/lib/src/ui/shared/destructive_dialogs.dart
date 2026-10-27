import 'package:flutter/material.dart';
import 'package:simutil_app/src/ui/design/design.dart';
import 'package:simutil_core/simutil_core.dart';

/// Asks before deleting [device]; the AVD/simulator and its data go away
/// and the guard cannot bring them back.
Future<bool> confirmDeleteDevice(BuildContext context, Device device) async {
  final t = SimuTokens.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: t.panel,
      title: Text('Delete “${device.name}”?', style: t.title),
      content: Text(
        'Deletes the ${device.os == DeviceOs.android ? 'AVD' : 'simulator'} '
        'and all of its data. This cannot be undone.',
        style: t.body,
      ),
      actions: [
        SimuButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        SimuButton(
          label: 'Delete',
          primary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Wiping asks for the device name, like `rm -rf` asks for a confirmation:
/// a stray click must not erase a phone.
Future<bool> confirmWipeDevice(BuildContext context, Device device) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final t = SimuTokens.of(context);
      return StatefulBuilder(
        builder: (context, setState) {
          final matches = controller.text.trim() == device.name;
          return AlertDialog(
            backgroundColor: t.panel,
            title: Text('Wipe “${device.name}”?', style: t.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Erases apps, settings and snapshots on ${device.name}. '
                  'Type the device name to confirm.',
                  style: t.body,
                ),
                const SizedBox(height: 12),
                SimuTextField(
                  controller: controller,
                  hint: device.name,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              SimuButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              SimuButton(
                label: 'Wipe',
                primary: matches,
                onPressed: matches
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return confirmed ?? false;
}
