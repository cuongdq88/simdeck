import Foundation

struct DeviceSettings: Codable, Equatable {
  /// Overrides the global headless default for this device.
  var headless: Bool?
  var coldBoot = false
  /// `virtualscene`, `emulated`, `none` or `webcamN`.
  var cameraBack: String?
  var cameraFront: String?
  var showFrame: Bool?
}

/// Per-device launch and view settings, persisted across launches.
@MainActor
final class DeviceSettingsStore: ObservableObject {
  @Published private(set) var devices: [String: DeviceSettings] = [:]
  @Published var headlessDefault = true

  private let url: URL

  init() {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSHomeDirectory())
    let folder = support.appendingPathComponent("SimDeck", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    url = folder.appendingPathComponent("settings.json")
    load()
  }

  func settings(for device: Device) -> DeviceSettings {
    devices[device.key] ?? DeviceSettings()
  }

  func update(_ device: Device, _ change: (inout DeviceSettings) -> Void) {
    update(key: device.key, change)
  }

  func update(key: String, _ change: (inout DeviceSettings) -> Void) {
    var value = devices[key] ?? DeviceSettings()
    change(&value)
    devices[key] = value
    save()
  }

  func isHeadless(_ device: Device) -> Bool {
    settings(for: device).headless ?? headlessDefault
  }

  func showFrame(_ device: Device) -> Bool {
    settings(for: device).showFrame ?? true
  }

  private func load() {
    guard let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(Stored.self, from: data)
    else { return }
    devices = decoded.devices
    headlessDefault = decoded.headlessDefault
  }

  private func save() {
    let stored = Stored(devices: devices, headlessDefault: headlessDefault)
    guard let data = try? JSONEncoder().encode(stored) else { return }
    try? data.write(to: url, options: .atomic)
  }

  private struct Stored: Codable {
    var devices: [String: DeviceSettings]
    var headlessDefault: Bool
  }
}
