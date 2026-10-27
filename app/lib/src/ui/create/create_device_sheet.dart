import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bloc_signals_flutter/bloc_signals_flutter.dart';
import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_app/src/bridge/emu_models.dart';
import 'package:simutil_app/src/devices/devices_cubit.dart';
import 'package:simutil_app/src/di.dart';
import 'package:simutil_app/src/ui/create/create_device_controller.dart';
import 'package:simutil_app/src/ui/design/design.dart';
import 'package:simutil_core/simutil_core.dart';
import 'package:simutil_shared/simutil_shared.dart';

/// Opens the Create / Edit Device sheet; [edit] switches it to Edit mode.
Future<void> showCreateDeviceSheet(
  BuildContext context, {
  CreateDeviceController? edit,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (context) => CreateDeviceSheet(controller: edit),
);

/// Opens Edit for a shut-down Android emulator: reads its `config.ini`
/// through the helper, after the same guard the delete path uses.
Future<void> showEditDeviceSheet(BuildContext context, Device device) async {
  final verdict = await getIt<DeletionGuard>().checkAvd(device.name);
  if (!context.mounted) return;
  if (verdict.code == 'not_found' || verdict.code == 'shared_dir') {
    // A shared directory would rewrite a config.ini other AVDs also boot.
    context.read<DevicesCubit>().notify(
      verdict.message ?? 'Cannot edit this AVD',
      error: true,
    );
    return;
  }
  final bridge = getIt<EmuBridge>();
  try {
    final config = await bridge.avdShow(device.name);
    if (!context.mounted) return;
    await showCreateDeviceSheet(
      context,
      edit: CreateDeviceController.forEdit(config, bridge: bridge),
    );
  } on Object catch (e) {
    if (context.mounted) {
      context.read<DevicesCubit>().notify('$e', error: true);
    }
  }
}

/// One form for both platforms and both modes (spec §9).
class CreateDeviceSheet extends StatefulWidget {
  const CreateDeviceSheet({super.key, this.controller, this.onCreate});

  /// Edit mode; null means Create.
  final CreateDeviceController? controller;

  /// Called with the new device name after a successful submit.
  final void Function(String name)? onCreate;

  @override
  State<CreateDeviceSheet> createState() => _CreateDeviceSheetState();
}

class _CreateDeviceSheetState extends State<CreateDeviceSheet> {
  late final CreateDeviceController _c =
      widget.controller ?? CreateDeviceController.forCreate();
  final _nameController = TextEditingController();
  final _ramController = TextEditingController();
  final _storageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _adoptForm();
    _c.addListener(_onController);
    if (!_c.isEditing) _c.loadCatalogs();
  }

  void _adoptForm() {
    final form = _c.form;
    _nameController.text = form.name;
    _ramController.text = form.ramMb?.toString() ?? '';
    _storageController.text = form.storage ?? '';
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
    if (_c.createdName case final name?) {
      widget.onCreate?.call(name);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    if (widget.controller == null) _c.dispose();
    _nameController.dispose();
    _ramController.dispose();
    _storageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SimuTokens.of(context);
    final form = _c.form;
    final editing = _c.isEditing;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SimuPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    editing ? LucideIcons.pencil : LucideIcons.plus,
                    size: 16,
                    color: t.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(editing ? 'Edit device' : 'New device', style: t.title),
                  const Spacer(),
                  SimuIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!editing)
                SegmentedButton<FormPlatform>(
                  segments: const [
                    ButtonSegment(
                      value: FormPlatform.android,
                      label: Text('Android'),
                      icon: Icon(LucideIcons.smartphone, size: 14),
                    ),
                    ButtonSegment(
                      value: FormPlatform.ios,
                      label: Text('iOS'),
                      icon: Icon(LucideIcons.apple, size: 14),
                    ),
                  ],
                  selected: {form.platform},
                  onSelectionChanged: (selection) =>
                      _c.setPlatform(selection.first),
                ),
              const SizedBox(height: 14),
              if (form.platform == FormPlatform.android)
                ..._androidFields(t)
              else
                ..._iosFields(t),
              if (_c.error case final error?) ...[
                const SizedBox(height: 12),
                Text(error, style: t.body.copyWith(color: t.danger)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Text(_summary(t), style: t.caption)),
                  SimuButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  SimuButton(
                    label: editing ? 'Update' : 'Create',
                    primary: true,
                    onPressed: _c.canSubmit ? _c.submit : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _androidFields(SimuTokens t) {
    final form = _c.form;
    final locked = _c.isEditing;
    return [
      _label(t, 'Name'),
      SimuTextField(
        controller: _nameController,
        hint: 'ZZ_MyDevice',
        onChanged: _c.setName,
      ),
      if (_c.nameError case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(error, style: t.caption.copyWith(color: t.warning)),
        ),
      const SizedBox(height: 12),
      if (!locked) ...[
        _label(t, 'Hardware profile'),
        _dropdown<AvdProfile>(
          value: form.profile,
          hint: _c.loading ? 'Loading profiles…' : 'Choose a profile',
          items: _c.profiles,
          label: (p) => p.screen.isEmpty ? p.name : '${p.name} · ${p.screen}',
          onChanged: _c.setProfile,
        ),
        const SizedBox(height: 12),
        _label(t, 'API level (installed images)'),
        _dropdown<int>(
          value: form.api,
          hint: _c.installedApis.isEmpty
              ? 'No installed image; install one in Runtimes'
              : 'Choose an API',
          items: _c.installedApis,
          label: (api) => 'API $api',
          onChanged: (api) => _c
            ..setApi(api)
            ..loadTags(api),
        ),
        const SizedBox(height: 12),
        _label(t, 'Tag and ABI'),
        _dropdown<AvdTag>(
          value: form.tag,
          hint: form.api == null ? 'Choose an API first' : 'Choose a tag',
          items: _c.tags,
          label: (tag) =>
              '${tag.tag} · ${tag.abi}${tag.installed ? '' : ' (not installed)'}',
          onChanged: _c.setTag,
        ),
      ],
      const SizedBox(height: 12),
      _label(t, 'RAM (MB)'),
      SimuTextField(
        controller: _ramController,
        hint: '2048',
        keyboardType: TextInputType.number,
        onChanged: (value) =>
            _c.setRam(int.tryParse(value.trim().isEmpty ? '' : value)),
      ),
      const SizedBox(height: 12),
      _label(t, 'Storage'),
      SimuTextField(
        controller: _storageController,
        hint: '8G',
        onChanged: (value) =>
            _c.setStorage(value.trim().isEmpty ? null : value.trim()),
      ),
      if (!locked) ...[
        const SizedBox(height: 6),
        _advanced(t),
      ],
    ];
  }

  List<Widget> _iosFields(SimuTokens t) {
    final form = _c.form;
    return [
      _label(t, 'Name'),
      SimuTextField(
        controller: _nameController,
        hint: 'ZZ_MySimulator',
        onChanged: _c.setName,
      ),
      const SizedBox(height: 12),
      _label(t, 'Device type'),
      _dropdown<IosDeviceType>(
        value: form.iosDeviceType,
        hint: _c.loading ? 'Loading…' : 'Choose a device type',
        items: _c.iosDeviceTypes,
        label: (type) => type.name,
        onChanged: _c.setIosDeviceType,
      ),
      const SizedBox(height: 12),
      _label(t, 'Runtime'),
      _dropdown<IosRuntime>(
        value: form.iosRuntime,
        hint: _c.iosRuntimes.isEmpty
            ? 'No runtime installed; get one in Xcode › Settings › Platforms'
            : 'Choose a runtime',
        items: _c.iosRuntimes,
        label: (runtime) => runtime.name,
        onChanged: _c.setIosRuntime,
      ),
    ];
  }

  Widget _advanced(SimuTokens t) {
    final form = _c.form;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text('Advanced', style: t.caption),
        children: [
          _label(t, 'Back camera'),
          _dropdown<String>(
            value: form.camera,
            hint: 'AVD default',
            items: const ['virtualscene', 'emulated', 'none'],
            label: (value) => value,
            onChanged: _c.setCamera,
          ),
          const SizedBox(height: 10),
          _label(t, 'Orientation'),
          _dropdown<String>(
            value: form.orientation,
            hint: 'Portrait',
            items: const ['portrait', 'landscape'],
            label: (value) => value,
            onChanged: _c.setOrientation,
          ),
          const SizedBox(height: 10),
          _label(t, 'SD card (update only)'),
          _dropdown<String>(
            value: form.sdcard,
            hint: 'Unchanged',
            items: const ['none', '512M', '1G', '2G'],
            label: (value) => value == 'none' ? 'No card' : value,
            onChanged: _c.setSdcard,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Hardware keyboard', style: t.caption),
              const Spacer(),
              Switch(
                value: form.keyboard ?? true,
                onChanged: _c.setKeyboard,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _summary(SimuTokens t) {
    final form = _c.form;
    if (form.platform == FormPlatform.ios) {
      return form.iosRuntime == null
          ? 'Needs an installed runtime'
          : '${form.iosDeviceType?.name ?? ''} · ${form.iosRuntime!.name}';
    }
    final needs = _c.requiredSpaceLabel;
    return needs ?? 'Disk space checked before download';
  }

  Widget _label(SimuTokens t, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: t.overline),
  );

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T) label,
    required void Function(T) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      hint: Text(hint, style: SimuTokens.of(context).caption),
      items: [
        for (final item in items)
          DropdownMenuItem(value: item, child: Text(label(item))),
      ],
      onChanged: (picked) {
        if (picked != null) onChanged(picked);
      },
    );
  }
}
