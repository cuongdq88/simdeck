import Foundation

enum StreamLayout: String, CaseIterable, Identifiable {
  case grid
  case spotlightVertical
  case spotlightHorizontal

  var id: String { rawValue }

  var label: String {
    switch self {
    case .grid: return "Grid"
    case .spotlightVertical: return "Spotlight: large left, strip right"
    case .spotlightHorizontal: return "Spotlight: large top, strip bottom"
    }
  }

  var symbol: String {
    switch self {
    case .grid: return "square.grid.2x2"
    case .spotlightVertical: return "rectangle.righthalf.inset.filled"
    case .spotlightHorizontal: return "rectangle.bottomhalf.inset.filled"
    }
  }
}

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
  @Published private(set) var layout: StreamLayout = .grid
  @Published private(set) var spotlightKey: String?

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

  func setLayout(_ value: StreamLayout) {
    layout = value
    save()
  }

  func setSpotlight(_ key: String?) {
    spotlightKey = key
    save()
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
    layout = StreamLayout(rawValue: decoded.layout ?? "") ?? .grid
    spotlightKey = decoded.spotlightKey
  }

  private func save() {
    let stored = Stored(
      devices: devices,
      headlessDefault: headlessDefault,
      layout: layout.rawValue,
      spotlightKey: spotlightKey)
    guard let data = try? JSONEncoder().encode(stored) else { return }
    try? data.write(to: url, options: .atomic)
  }

  private struct Stored: Codable {
    var devices: [String: DeviceSettings]
    var headlessDefault: Bool
    var layout: String?
    var spotlightKey: String?
  }
}
