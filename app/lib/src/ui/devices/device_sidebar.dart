import 'dart:io';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simutil_app/src/di.dart';
import 'package:simutil_app/src/logging/debug_log.dart';
import 'package:simutil_app/src/ui/connect/connect_dialog.dart';
import 'package:simutil_app/src/ui/create/create_device_sheet.dart';
import 'package:simutil_app/src/devices/devices_cubit.dart';
import 'package:simutil_app/src/devices/devices_state.dart';
import 'package:simutil_app/src/ui/design/design.dart';
import 'package:simutil_app/src/ui/devices/device_row.dart';
import 'package:simutil_app/src/ui/devices/device_search_field.dart';
import 'package:simutil_app/src/ui/toasts/update_toast.dart';
import 'package:simutil_app/src/update/app_update_cubit.dart';
import 'package:simutil_core/simutil_core.dart';
import 'package:window_manager/window_manager.dart';

/// Brand header, search and refresh, and the device sections.
class DeviceSidebar extends StatefulWidget {
  const DeviceSidebar({super.key});

  @override
  State<DeviceSidebar> createState() => _DeviceSidebarState();
}

class _DeviceSidebarState extends State<DeviceSidebar> {
  String _query = '';

  /// Group keys the user collapsed; kept for the session.
  final _collapsed = <String>{};

  void _toggle(String group) => setState(
    () => _collapsed.contains(group)
        ? _collapsed.remove(group)
        : _collapsed.add(group),
  );

  List<Device> _filter(List<Device> devices) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return devices;
    return [
      for (final d in devices)
        if (d.name.toLowerCase().contains(query)) d,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sidebar,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          _SearchRow(onChanged: (query) => setState(() => _query = query)),
          Expanded(
            child: BlocSignalBuilder<DevicesCubit, DevicesState>(
              builder: (context, state) => ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                children: [
                  if (state.loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: SimuSpinner()),
                    ),
                  _Section(
                    title: 'Running',
                    devices: _filter(runningDevices(state)),
                    state: state,
                    collapsed: _collapsed.contains('running'),
                    onToggle: () => _toggle('running'),
                    showWhenEmpty: true,
                  ),
                  for (final (key, title, devices) in [
                    ('android-devices', 'Android devices', state.androidDevices),
                    (
                      'android-emulators',
                      'Android emulators',
                      state.androidEmulators,
                    ),
                    ('ios-devices', 'iOS devices', state.iosDevices),
                    ('ios-simulators', 'iOS simulators', state.iosSimulators),
                  ])
                    _Section(
                      title: title,
                      devices: _filter(idleDevices(devices)),
                      state: state,
                      collapsed: _collapsed.contains(key),
                      onToggle: () => _toggle(key),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
      child: Row(
        children: [
          Expanded(child: DeviceSearchField(onChanged: onChanged)),
          const SizedBox(width: 4),
          SimuIconButton(
            icon: LucideIcons.plus,
            tooltip: 'New device (c)',
            size: 15,
            onPressed: () => showCreateDeviceSheet(context),
          ),
          SimuIconButton(
            icon: LucideIcons.wifi,
            tooltip: 'Connect a device over Wi-Fi',
            size: 15,
            onPressed: () => showConnectDeviceDialog(context),
          ),
          SimuIconButton(
            icon: LucideIcons.refreshCw,
            tooltip: 'Refresh devices',
            size: 15,
            onPressed: () => context.read<DevicesCubit>().refresh(),
          ),
        ],
      ),
    );
  }
}

/// Logo and name; tapping the logo five times in a row toggles the debug
/// panel.
class _Brand extends StatefulWidget {
  const _Brand();

  @override
  State<_Brand> createState() => _BrandState();
}

class _BrandState extends State<_Brand> {
  static const _taps = 5;
  static const _window = Duration(seconds: 2);
  final _tapTimes = <DateTime>[];

  void _onLogoTap() {
    final now = DateTime.now();
    _tapTimes
      ..removeWhere((t) => now.difference(t) > _window)
      ..add(now);
    if (_tapTimes.length < _taps) return;
    _tapTimes.clear();
    getIt<DebugLog>().toggle();
  }

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    // The drag area sits behind the logo: its double-tap (maximize) would
    // otherwise swallow the logo taps.
    return Stack(
      children: [
        const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
        Padding(
          // macOS draws the traffic lights over the top of the sidebar.
          padding: EdgeInsets.fromLTRB(14, Platform.isMacOS ? 40 : 14, 14, 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: _onLogoTap,
                child: Image.asset(
                  'assets/logo.png',
                  width: 24,
                  height: 24,
                  filterQuality: FilterQuality.medium,
                  semanticLabel: 'SimDeck',
                ),
              ),
              const SizedBox(width: 10),
              Text('SimDeck', style: t.title),
              const _UpdateButton(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown while a newer release exists; reopens the update toast.
class _UpdateButton extends StatelessWidget {
  const _UpdateButton();

  @override
  Widget build(BuildContext context) {
    // Release builds register no AppUpdateCubit at all (spec §12.2).
    if (!getIt.isRegistered<AppUpdateCubit>()) return const SizedBox.shrink();
    final update = context.value<AppUpdateCubit, AppUpdate?>();
    if (update == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: SimuIconButton(
        icon: LucideIcons.circleArrowUp,
        tooltip: 'SimDeck ${update.version} is available',
        color: SimuTokens.of(context).accent,
        onPressed: () => showUpdateToast(context, update),
      ),
    );
  }
}

/// Everything the device lists report as running, in sidebar order, so the
/// RUNNING group can sit on top of the platform groups.
List<Device> runningDevices(DevicesState state) => [
  for (final device in state.all)
    if (device.isRunning) device,
];

/// The devices of a platform group the RUNNING group does not already show.
List<Device> idleDevices(List<Device> devices) => [
  for (final device in devices)
    if (!device.isRunning) device,
];

/// One collapsible sidebar group: a clickable header with a count, then the
/// rows.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.devices,
    required this.state,
    required this.collapsed,
    required this.onToggle,
    this.showWhenEmpty = false,
  });

  final String title;
  final List<Device> devices;
  final DevicesState state;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Keep the header visible with a 0 count (RUNNING must not vanish).
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty && !showWhenEmpty) return const SizedBox.shrink();
    final t = SimuTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SimuHoverable(
          onTap: onToggle,
          builder: (context, hovered) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Row(
              children: [
                Icon(
                  collapsed ? LucideIcons.chevronRight : LucideIcons.chevronDown,
                  size: 13,
                  color: hovered ? t.text : t.textFaint,
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(title.toUpperCase(), style: t.overline)),
                Text('${devices.length}', style: t.mono.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ),
        if (!collapsed)
          for (final device in devices)
            DeviceRow(device: device, state: state),
      ],
    );
  }
}
