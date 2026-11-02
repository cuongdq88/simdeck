import Foundation

/// USB-connected iPhones and iPads, listed through `devicectl`.
enum DevicectlService {
  static func listPhysicalDevices() async -> [Device] {
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("simdeck-devicectl-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: output) }
    // Xcode 27 lists simulators too, so ask for physical devices; older
    // Xcodes reject the filter and list hardware only.
    var result = await run(filter: true, output: output)
    if !result.ok {
      result = await run(filter: false, output: output)
    }
    guard result.ok, let data = try? Data(contentsOf: output),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [] }
    return parse(json)
  }

  private static func run(filter: Bool, output: URL) async -> ProcessResult {
    var arguments = ["devicectl", "list", "devices"]
    if filter {
      arguments += ["--filter", "Reality = 'physical'"]
    }
    arguments += ["-j", output.path]
    return await ProcessRunner.run("/usr/bin/xcrun", arguments, timeout: 45)
  }

  static func parse(_ json: [String: Any]) -> [Device] {
    let result = json["result"] as? [String: Any] ?? [:]
    let list = result["devices"] as? [[String: Any]] ?? []
    var devices: [Device] = []
    for entry in list {
      let hardware = entry["hardwareProperties"] as? [String: Any]
      let properties = entry["deviceProperties"] as? [String: Any]
      let connection = entry["connectionProperties"] as? [String: Any]

      let nestedHardware = (entry["properties"] as? [String: Any])?["hardware"]
        as? [String: Any]
      let reality = (hardware?["reality"] as? String)
        ?? (nestedHardware?["reality"] as? String)
      if reality == "simulated" { continue }

      let identifier = (hardware?["udid"] as? String)
        ?? (entry["identifier"] as? String) ?? ""
      let name = properties?["name"] as? String ?? ""
      let version = properties?["osVersionNumber"] as? String ?? ""
      guard !identifier.isEmpty, !name.isEmpty else { continue }

      // A device on USB or Wi-Fi has a transport; its tunnel stays
      // disconnected until Xcode or devicectl uses it.
      let tunnel = connection?["tunnelState"] as? String
      let connected = connection?["transportType"] != nil
        || !["unavailable", "disconnected"].contains(tunnel)
      if !connected { continue }

      devices.append(
        Device(
          key: "ios-device:\(identifier)",
          rawID: identifier,
          name: name,
          os: .ios,
          kind: .physical,
          platform: version.isEmpty ? "iOS" : "iOS \(version)",
          state: .booted,
          serial: nil,
          avdName: nil))
    }
    return devices
  }
}
