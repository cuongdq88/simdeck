import 'dart:io';

import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simutil_app/src/di.dart';
import 'package:simutil_app/src/logging/debug_log.dart';
import 'package:simutil_app/src/ui/connect/connect_dialog.dart';
import 'package:simutil_app/src/ui/create/create_device_controller.dart';
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
              builder: (context, state) {
                // One flat item list so ListView.builder only builds the rows
                // on screen: 25+ devices should not cost a widget each.
                final items = <_SidebarItem>[
                  if (state.loading) const _LoadingItem(),
                  ..._group(
                    key: 'running',
                    title: 'Running',
                    devices: runningDevices(state),
                    state: state,
                    showWhenEmpty: true,
                    running: true,
                  ),
                  ..._group(
                    key: 'android-devices',
                    title: 'Android devices',
                    devices: state.androidDevices,
                    state: state,
                  ),
                  ..._group(
                    key: 'android-emulators',
                    title: 'Android emulators',
                    devices: state.androidEmulators,
                    state: state,
                    platform: FormPlatform.android,
                    showWhenEmpty: true,
                  ),
                  ..._group(
                    key: 'ios-devices',
                    title: 'iOS devices',
                    devices: state.iosDevices,
                    state: state,
                  ),
                  ..._group(
                    key: 'ios-simulators',
                    title: 'iOS simulators',
                    devices: state.iosSimulators,
                    state: state,
                    platform: FormPlatform.ios,
                    showWhenEmpty: true,
                  ),
                ];
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: items.length,
                  itemBuilder: (context, index) => switch (items[index]) {
                    _LoadingItem() => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: SimuSpinner()),
                    ),
                    _GroupItem(:final header) => header,
                    _DeviceItem(:final device) => DeviceRow(
                      device: device,
                      state: state,
                    ),
                  },
                );
              },
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

/// What one group lists: RUNNING keeps running devices, the platform groups
/// drop them so nothing is shown twice.
List<Device> groupDevices(List<Device> devices, {required bool running}) =>
    running ? devices : idleDevices(devices);

/// The devices of a platform group the RUNNING group does not already show.
List<Device> idleDevices(List<Device> devices) => [
  for (final device in devices)
    if (!device.isRunning) device,
];

sealed class _SidebarItem {
  const _SidebarItem();
}

class _LoadingItem extends _SidebarItem {
  const _LoadingItem();
}

/// A group header; [header] is built only when this item is on screen.
class _GroupItem extends _SidebarItem {
  const _GroupItem(this.header);

  final Widget header;
}

class _DeviceItem extends _SidebarItem {
  const _DeviceItem(this.device);

  final Device device;
}

extension on _DeviceSidebarState {
  /// Header plus (unless collapsed) one item per device, already filtered.
  /// [running] keeps the devices as given: the RUNNING group is built from
  /// running devices, the platform groups drop them because RUNNING has them.
  List<_SidebarItem> _group({
    required String key,
    required String title,
    required List<Device> devices,
    required DevicesState state,
    FormPlatform? platform,
    bool showWhenEmpty = false,
    bool running = false,
  }) {
    final visible = _filter(groupDevices(devices, running: running));
    if (visible.isEmpty && !showWhenEmpty) return const [];
    final collapsed = _collapsed.contains(key);
    return [
      _GroupItem(
        _GroupHeader(
          title: title,
          count: visible.length,
          collapsed: collapsed,
          onToggle: () => _toggle(key),
          addTooltip: switch (platform) {
            FormPlatform.android => 'New Android emulator',
            FormPlatform.ios => 'New iOS simulator',
            null => null,
          },
          onAdd: switch (platform) {
            FormPlatform.android => () => showCreateDeviceSheet(
              context,
              platform: FormPlatform.android,
            ),
            FormPlatform.ios => () => showCreateDeviceSheet(
              context,
              platform: FormPlatform.ios,
            ),
            null => null,
          },
        ),
      ),
      if (!collapsed)
        for (final device in visible) _DeviceItem(device),
    ];
  }
}

/// Collapsible group header: chevron, title, count, and the group's add
/// button at the far right.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.onAdd,
    this.addTooltip,
  });

  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;
  final String? addTooltip;

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    return SimuHoverable(
      onTap: onToggle,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
        child: Row(
          children: [
            Icon(
              collapsed ? LucideIcons.chevronRight : LucideIcons.chevronDown,
              size: 13,
              color: hovered ? t.text : t.textFaint,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(title.toUpperCase(), style: t.overline)),
            Text('$count', style: t.mono.copyWith(fontSize: 11)),
            if (onAdd case final add?) ...[
              const SizedBox(width: 4),
              SimuIconButton(
                icon: LucideIcons.plus,
                tooltip: addTooltip ?? 'New device',
                size: 13,
                onPressed: add,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
