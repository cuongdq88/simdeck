import Foundation

/// One wireless-debugging endpoint advertised over mDNS.
struct AdbMdnsService: Identifiable, Hashable {
  let name: String
  /// `_adb-tls-pairing._tcp` or `_adb-tls-connect._tcp`.
  let type: String
  /// `host:port`.
  let address: String

  var id: String { "\(type):\(address)" }
  var isPairing: Bool { type.contains("pairing") }
  var kind: String { isPairing ? "Pairing" : "Connect" }
}

enum AdbService {
  struct Entry: Hashable {
    let serial: String
    let state: String
    var isReady: Bool { state == "device" }
  }

  static func devices() async -> [Entry] {
    let result = await ProcessRunner.run(ShellEnv.adbPath, ["devices"], timeout: 15)
    guard result.ok else { return [] }
    return result.stdout
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { line in
        !line.isEmpty
          && !line.hasPrefix("List of devices")
          && !line.hasPrefix("*")
          && !line.hasPrefix("adb")
          && !line.hasPrefix("daemon")
      }
      .compactMap { line in
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        return Entry(serial: parts[0], state: parts[1])
      }
  }

  /// AVD name of a running emulator serial, from `adb emu avd name`.
  static func avdName(serial: String) async -> String? {
    let result = await ProcessRunner.run(
      ShellEnv.adbPath, ["-s", serial, "emu", "avd", "name"], timeout: 10)
    guard result.ok else { return nil }
    return result.stdout
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty && $0 != "OK" }
  }

  /// Running AVD name → adb serial.
  static func runningAvds() async -> [String: String] {
    let entries = await devices()
    var map: [String: String] = [:]
    for entry in entries where entry.serial.hasPrefix("emulator-") {
      if let name = await avdName(serial: entry.serial) { map[name] = entry.serial }
    }
    return map
  }

  static func kill(serial: String) async -> Bool {
    let result = await ProcessRunner.run(
      ShellEnv.adbPath, ["-s", serial, "emu", "kill"], timeout: 15)
    return result.ok
  }

  static func shell(
    serial: String, _ arguments: [String], timeout: TimeInterval = 30
  ) async -> ProcessResult {
    await ProcessRunner.run(
      ShellEnv.adbPath, ["-s", serial, "shell"] + arguments, timeout: timeout)
  }

  // MARK: - Wireless debugging

  static func pair(hostPort: String, code: String) async -> ProcessResult {
    await ProcessRunner.run(
      ShellEnv.adbPath, ["pair", hostPort, code], timeout: 45)
  }

  static func connect(hostPort: String) async -> ProcessResult {
    await ProcessRunner.run(
      ShellEnv.adbPath, ["connect", hostPort], timeout: 25)
  }

  static func disconnect(hostPort: String) async -> ProcessResult {
    await ProcessRunner.run(
      ShellEnv.adbPath, ["disconnect", hostPort], timeout: 15)
  }

  /// Adb's own mDNS browser; pairing and connect endpoints for devices that
  /// have wireless debugging on.
  static func mdnsServices() async -> [AdbMdnsService] {
    let result = await ProcessRunner.run(
      ShellEnv.adbPath, ["mdns", "services"], timeout: 15)
    guard result.ok else { return [] }
    var services: [AdbMdnsService] = []
    for line in result.stdout.components(separatedBy: .newlines) {
      let parts = line
        .split(whereSeparator: { $0 == "\t" || $0 == " " })
        .map(String.init)
        .filter { !$0.isEmpty }
      guard parts.count >= 3, parts[1].contains("_adb-tls-") else { continue }
      services.append(
        AdbMdnsService(name: parts[0], type: parts[1], address: parts[2]))
    }
    return services
  }
}
