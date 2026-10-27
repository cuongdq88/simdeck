import 'package:simutil_app/src/bridge/emu_bridge.dart';
import 'package:simutil_core/simutil_core.dart';
import 'package:simutil_app/src/mcp/mcp_server.dart';
import 'package:simutil_app/src/mcp/tools/tool_context.dart';

/// A freshly created device is not in the sidebar until a refresh; wait for
/// it so `create_*` followed by `start_device` works without a manual poll.
Future<void> refreshUntilNamed(ToolContext context, String name) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    await context.devices.refresh(silent: true);
    if (context.devices.stateValue.all.any((d) => d.name == name)) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

/// The cubit's list lags a shutdown by a refresh; wait until it agrees, or
/// `delete` returns early and the AVD stays on disk.
Future<Device> waitForShutdown(ToolContext context, String id) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final current = context.devices.stateValue.all
        .where((d) => d.id == id)
        .firstOrNull;
    if (current == null || current.state == DeviceState.shutdown) {
      return current ?? (throw StateError('device disappeared'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await context.devices.refresh(silent: true);
  }
  throw StateError('device is still running; stop it first');
}

/// Creating and removing devices through the `emu` helper, so an agent in
/// another project can go from nothing to a running screen.
List<McpTool> createTools(ToolContext context) {
  EmuBridge bridge() =>
      context.emu ??
      (throw StateError('The device helper is not wired into this process'));

  return [
    McpTool(
      name: 'get_device_catalogs',
      description:
          'What can be created right now: installed Android APIs with their '
          'tag/ABI pairs, hardware profiles, and the iOS device types and '
          'installed runtimes. Call this before create_avd/create_simulator.',
      handler: (args) async {
        final emu = bridge();
        final profiles = await emu.avdProfiles();
        final images = await emu.images();
        final apis = <String>{
          for (final image in images)
            if (image.installed) image.api,
        }.toList()..sort((a, b) => b.compareTo(a));

        final byApi = <Map<String, Object?>>[];
        for (final api in apis) {
          final number = int.tryParse(api);
          if (number == null) continue; // 36.1 cannot be created yet.
          final tags = await emu.avdTags(number);
          byApi.add({
            'api': api,
            'tags': [
              for (final tag in tags)
                if (tag.installed) {'tag': tag.tag, 'abi': tag.abi},
            ],
          });
        }

        return context.text({
          'android': {
            'apis': byApi,
            'profiles': [
              for (final profile in profiles)
                {
                  'id': profile.id,
                  'name': profile.name,
                  'screen': profile.screen,
                },
            ],
          },
          'ios': {
            'deviceTypes': [
              for (final type in await emu.iosDeviceTypes())
                {'id': type.id, 'name': type.name},
            ],
            'runtimes': [
              for (final runtime in await emu.iosRuntimes())
                {'id': runtime.id, 'name': runtime.name},
            ],
          },
        });
      },
    ),
    McpTool(
      name: 'create_avd',
      description:
          'Create an Android AVD from an installed system image, then use '
          'start_device to boot it headless. Get api/tag/abi/device from '
          'get_device_catalogs. Fails with image_missing when the image is '
          'not installed (install it in SimDeck › SDK Manager).',
      properties: {
        'name': {'type': 'string', 'description': 'AVD name, e.g. ZZ_Agent'},
        'api': {'type': 'integer', 'description': 'API level, e.g. 36'},
        'tag': {'type': 'string', 'description': 'e.g. google_apis_playstore'},
        'abi': {'type': 'string', 'description': 'e.g. arm64-v8a'},
        'device': {
          'type': 'string',
          'description': 'Hardware profile id from get_device_catalogs',
        },
        'ram': {'type': 'integer', 'description': 'RAM in MB, e.g. 2048'},
        'storage': {'type': 'string', 'description': 'Data partition, e.g. 8G'},
        'camera': {
          'type': 'string',
          'description': 'virtualscene, emulated, none',
        },
        'orientation': {
          'type': 'string',
          'description': 'portrait or landscape',
        },
        'keyboard': {'type': 'boolean'},
      },
      required: ['name', 'api', 'tag', 'abi', 'device'],
      handler: (args) async {
        final result = await bridge().run([
          'avd',
          'create',
          '--name',
          '${args['name']}',
          '--api',
          '${args['api']}',
          '--tag',
          '${args['tag']}',
          '--abi',
          '${args['abi']}',
          '--device',
          '${args['device']}',
          if (args['ram'] != null) ...['--ram', '${args['ram']}'],
          if (args['storage'] != null) ...['--storage', '${args['storage']}'],
          if (args['camera'] != null) ...['--camera', '${args['camera']}'],
          if (args['orientation'] != null) ...[
            '--orientation',
            '${args['orientation']}',
          ],
          if (args['keyboard'] != null) ...[
            '--keyboard',
            '${args['keyboard']}',
          ],
        ], (json) => json);
        await refreshUntilNamed(context, '${args['name']}');
        return context.text(result as Object);
      },
    ),
    McpTool(
      name: 'create_simulator',
      description:
          'Create an iOS simulator from an installed runtime (ids from '
          'get_device_catalogs), then start_device to boot it headless.',
      properties: {
        'name': {'type': 'string'},
        'deviceType': {
          'type': 'string',
          'description': 'e.g. …SimDeviceType.iPhone-17',
        },
        'runtime': {
          'type': 'string',
          'description': 'e.g. …SimRuntime.iOS-26-5',
        },
      },
      required: ['name', 'deviceType', 'runtime'],
      handler: (args) async {
        final result = await bridge().run([
          'ios',
          'create',
          '--device-type',
          '${args['deviceType']}',
          '--runtime',
          '${args['runtime']}',
          '--name',
          '${args['name']}',
        ], (json) => json);
        await refreshUntilNamed(context, '${args['name']}');
        return context.text(result as Object);
      },
    ),
    McpTool(
      name: 'delete_device',
      description:
          'Delete a shut-down emulator/simulator. Refuses a running device, '
          'an AVD directory another .ini also points at, and a physical '
          'device — the same guard the app uses.',
      properties: deviceArg,
      required: ['device'],
      handler: (args) async {
        final device = context.find(args);
        if (device.type.isPhysical) {
          throw StateError('${device.name} is a physical device');
        }
        await waitForShutdown(context, device.id);
        await context.devices.delete(device);
        for (var attempt = 0; attempt < 10; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await context.devices.refresh(silent: true);
          final stillThere = context.devices.stateValue.all.any(
            (d) => d.id == device.id,
          );
          if (!stillThere) return context.text('Deleted ${device.name}');
        }
        return context.text(
          'Delete of ${device.name} did not complete; the deletion guard may '
          'have refused it (shared AVD directory, image in use).',
        );
      },
    ),
  ];
}
