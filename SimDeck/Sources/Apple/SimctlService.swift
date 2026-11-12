import Foundation

struct SimulatorDeviceType: Identifiable, Hashable {
  let id: String
  let name: String
}

struct SimulatorRuntime: Identifiable, Hashable {
  let id: String
  let name: String
  let version: String
  let isAvailable: Bool
  /// Device type identifiers this runtime can boot. Xcode can install a
  /// runtime for a single device (for example "iOS 27.2 (iPhone Duo)"), and
  /// `simctl create` rejects every other device type for it.
  let supportedDeviceTypes: [String]

  func supports(_ deviceTypeID: String) -> Bool {
    supportedDeviceTypes.contains(deviceTypeID)
  }
}

enum SimctlService {
  private static func run(_ arguments: [String], timeout: TimeInterval = 60) async -> ProcessResult {
    await ProcessRunner.run("/usr/bin/xcrun", ["simctl"] + arguments, timeout: timeout)
  }

  static func listDevices() async -> [Device] {
    let result = await run(["list", "devices", "-j"], timeout: 30)
    guard result.ok, let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let groups = json["devices"] as? [String: Any]
    else { return [] }

    var devices: [Device] = []
    for (runtime, value) in groups {
      guard let list = value as? [[String: Any]] else { continue }
      let platform = platformName(fromRuntime: runtime)
      for entry in list {
        guard let udid = entry["udid"] as? String,
          let name = entry["name"] as? String,
          (entry["isAvailable"] as? Bool) == true
        else { continue }
        let state = (entry["state"] as? String) ?? "Shutdown"
        devices.append(
          Device(
            key: "ios:\(udid)",
            rawID: udid,
            name: name,
            os: .ios,
            kind: .simulator,
            platform: platform,
            state: state.lowercased() == "booted" ? .booted : .shutdown,
            serial: nil,
            avdName: nil))
      }
    }
    return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func deviceTypes() async -> [SimulatorDeviceType] {
    let result = await run(["list", "devicetypes", "-j"], timeout: 30)
    guard result.ok, let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = json["devicetypes"] as? [[String: Any]]
    else { return [] }
    return list.compactMap { entry in
      guard let identifier = entry["identifier"] as? String,
        let name = entry["name"] as? String
      else { return nil }
      return SimulatorDeviceType(id: identifier, name: name)
    }
    .filter { entry in
      let name = entry.name
      return name.contains("iPhone") || name.contains("iPad")
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func runtimes() async -> [SimulatorRuntime] {
    let result = await run(["list", "runtimes", "-j"], timeout: 30)
    guard result.ok, let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = json["runtimes"] as? [[String: Any]]
    else { return [] }
    return list.compactMap { entry in
      guard let identifier = entry["identifier"] as? String,
        let name = entry["name"] as? String
      else { return nil }
      let available = (entry["isAvailable"] as? Bool) ?? false
      let supported = (entry["supportedDeviceTypes"] as? [[String: Any]] ?? [])
        .compactMap { $0["identifier"] as? String }
      return SimulatorRuntime(
        id: identifier,
        name: name,
        version: (entry["version"] as? String) ?? name,
        isAvailable: available,
        supportedDeviceTypes: supported)
    }
    .filter(\.isAvailable)
  }

  /// The first installed runtime that can boot [deviceTypeID].
  static func runtime(for deviceTypeID: String, in runtimes: [SimulatorRuntime]) -> SimulatorRuntime? {
    runtimes.first { $0.supports(deviceTypeID) }
  }

  static func create(name: String, deviceTypeID: String, runtimeID: String) async -> Result<String, Error> {
    let result = await run(["create", name, deviceTypeID, runtimeID], timeout: 120)
    let udid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.ok, !udid.isEmpty { return .success(udid) }
    return .failure(
      SimctlError(message: result.combined.isEmpty ? "simctl create failed" : result.combined))
  }

  static func boot(udid: String) async -> Bool {
    let result = await run(["boot", udid], timeout: 120)
    // "Unable to boot device in current state: Booted" is a success for us.
    return result.ok || result.combined.lowercased().contains("current state: booted")
  }

  static func shutdown(udid: String) async -> Bool {
    (await run(["shutdown", udid], timeout: 60)).ok
  }

  static func erase(udid: String) async -> Bool {
    (await run(["erase", udid], timeout: 120)).ok
  }

  static func delete(udid: String) async -> Bool {
    (await run(["delete", udid], timeout: 60)).ok
  }

  static func install(udid: String, path: String) async -> ProcessResult {
    await run(["install", udid, path], timeout: 300)
  }

  static func launch(udid: String, app: String) async -> ProcessResult {
    await run(["launch", "--terminate-running-process", udid, app], timeout: 60)
  }

  static func openSimulatorApp() async {
    _ = await ProcessRunner.run("/usr/bin/open", ["-a", "Simulator"], timeout: 15)
  }

  /// `iOS 17.2` from `com.apple.CoreSimulator.SimRuntime.iOS-17-2`.
  static func platformName(fromRuntime runtime: String) -> String {
    guard let last = runtime.split(separator: ".").last else { return runtime }
    let text = String(last).replacingOccurrences(of: "-", with: " ")
    let parts = text.split(separator: " ").map(String.init)
    guard parts.count > 1 else { return text }
    let head = parts[0]
    let version = parts.dropFirst().joined(separator: ".")
    return "\(head) \(version)"
  }
}

struct SimctlError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
