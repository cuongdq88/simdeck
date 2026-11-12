import Foundation

enum DeviceOS: String, Hashable {
  case android
  case ios

  var label: String { self == .android ? "Android" : "iOS" }
}

enum DeviceKind: String, Hashable {
  case simulator
  case physical
}

enum DeviceState: String, Hashable {
  case shutdown
  case booting
  case booted

  var label: String {
    switch self {
    case .shutdown: return "Shut down"
    case .booting: return "Booting"
    case .booted: return "Running"
    }
  }
}

/// One device row in the sidebar and one possible stream tile.
struct Device: Identifiable, Hashable {
  /// Stable identity across state changes (AVD name, simulator UDID, adb serial).
  let key: String
  /// The identifier the platform tools take: AVD name, simulator UDID, adb serial.
  let rawID: String
  let name: String
  let os: DeviceOS
  let kind: DeviceKind
  var platform: String
  var state: DeviceState
  /// adb serial while an Android device is running.
  var serial: String?
  /// AVD name for Android emulators, even while running.
  var avdName: String?
  /// Found over Wi-Fi only. iOS capture goes through CoreMediaIO, which
  /// exposes USB devices; the tile cannot open until the cable is connected.
  var requiresUSB = false

  var id: String { key }
  var isRunning: Bool { state == .booted }
  var isPhysical: Bool { kind == .physical }

  var symbol: String {
    switch (os, kind) {
    case (.android, .simulator): return "rectangle.3.group"
    case (.android, .physical): return "iphone.gen3"
    case (.ios, .simulator): return "iphone.gen3"
    case (.ios, .physical): return "iphone.gen3"
    }
  }

  var subtitle: String {
    [platform, state.label].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

enum TouchPhase {
  case down
  case move
  case up
}

enum DeviceButton: String, CaseIterable {
  case back
  case home
  case recents
  case lock
  case volumeUp
  case volumeDown

  var symbol: String {
    switch self {
    case .back: return "chevron.backward"
    case .home: return "circle"
    case .recents: return "square"
    case .lock: return "lock"
    case .volumeUp: return "speaker.plus"
    case .volumeDown: return "speaker.minus"
    }
  }
}

enum SessionStatus: Equatable {
  case connecting
  case live
  case failed(String)

  var isLive: Bool { self == .live }
}
