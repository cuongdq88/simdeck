import Foundation

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
}
