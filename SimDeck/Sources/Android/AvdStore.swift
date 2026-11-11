import Foundation

/// One AVD on disk, read straight from `$ANDROID_AVD_HOME`.
struct AvdInfo: Identifiable, Hashable {
  /// The on-disk AVD id: the `.ini` name and `.avd` directory.
  let name: String
  /// `avd.ini.displayname`, which is what the user typed (spaces included).
  let displayName: String
  let directory: URL
  let target: String?
  let imageSysdir: String?
  let tagId: String?
  let abi: String?
  let ramMb: Int?
  let dataPartition: String?

  var id: String { name }

  var api: Int? {
    for source in [target, imageSysdir] {
      guard let source else { continue }
      if let range = source.range(of: #"android-(\d+)"#, options: .regularExpression) {
        if let value = Int(source[range].filter(\.isNumber)) { return value }
      }
    }
    return nil
  }

  /// `image.sysdir.1` as an sdkmanager package id.
  var packageId: String? {
    guard let imageSysdir else { return nil }
    let trimmed = imageSysdir.hasSuffix("/") ? String(imageSysdir.dropLast()) : imageSysdir
    let parts = trimmed.split(separator: "/").map(String.init)
    guard let start = parts.firstIndex(of: "system-images") else { return nil }
    return parts[start...].joined(separator: ";")
  }

  var platform: String {
    guard let api else { return "Android" }
    let versions: [Int: String] = [
      21: "5.0", 22: "5.1", 23: "6", 24: "7.0", 25: "7.1", 26: "8.0", 27: "8.1",
      28: "9", 29: "10", 30: "11", 31: "12", 32: "12L", 33: "13", 34: "14",
      35: "15", 36: "16",
    ]
    if let version = versions[api] { return "Android \(version)" }
    return "Android API \(api)"
  }
}

enum AvdStore {
  /// Every `.ini` in the AVD home, sorted by name.
  static func list() -> [AvdInfo] {
    let home = URL(fileURLWithPath: ShellEnv.avdHome, isDirectory: true)
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: home, includingPropertiesForKeys: [.isRegularFileKey])
    else { return [] }

    return files
      .filter { $0.pathExtension == "ini" }
      .compactMap { load(ini: $0) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func load(name: String) -> AvdInfo? {
    let home = URL(fileURLWithPath: ShellEnv.avdHome, isDirectory: true)
    return load(ini: home.appendingPathComponent("\(name).ini"))
  }

  static func avdDirectory(for name: String) -> URL {
    let home = URL(fileURLWithPath: ShellEnv.avdHome, isDirectory: true)
    let ini = home.appendingPathComponent("\(name).ini")
    let values = parseINI(ini)
    if let path = values["path"], !path.isEmpty {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    if let rel = values["path.rel"], !rel.isEmpty {
      return home.appendingPathComponent(rel, isDirectory: true)
    }
    return home.appendingPathComponent("\(name).avd", isDirectory: true)
  }

  static func exists(name: String) -> Bool {
    let ini = URL(fileURLWithPath: ShellEnv.avdHome, isDirectory: true)
      .appendingPathComponent("\(name).ini")
    return FileManager.default.fileExists(atPath: ini.path)
      || FileManager.default.fileExists(atPath: avdDirectory(for: name).path)
  }

  /// Removes the `.avd` directory and its `.ini`, like `avdmanager delete avd`.
  static func delete(name: String) throws {
    let home = URL(fileURLWithPath: ShellEnv.avdHome, isDirectory: true)
    let ini = home.appendingPathComponent("\(name).ini")
    let dir = avdDirectory(for: name)
    if FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.removeItem(at: dir)
    }
    if FileManager.default.fileExists(atPath: ini.path) {
      try FileManager.default.removeItem(at: ini)
    }
  }

  /// What Android Studio's Wipe Data removes; the emulator rebuilds userdata.
  static let wipedFiles = [
    "userdata-qemu.img",
    "userdata-qemu.img.qcow2",
    "cache.img",
    "cache.img.qcow2",
    "snapshots",
  ]

  static func wipe(name: String) throws {
    let dir = avdDirectory(for: name)
    for file in wipedFiles {
      let url = dir.appendingPathComponent(file)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      try FileManager.default.removeItem(at: url)
    }
  }

  static func parseINI(_ url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for line in text.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=")
      else { continue }
      let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
      let value = String(trimmed[trimmed.index(after: equals)...])
        .trimmingCharacters(in: .whitespaces)
      values[key] = value
    }
    return values
  }

  private static func load(ini: URL) -> AvdInfo? {
    let values = parseINI(ini)
    let name = ini.deletingPathExtension().lastPathComponent
    let directory = avdDirectory(for: name)
    let config = parseINI(directory.appendingPathComponent("config.ini"))
    // A leftover .ini with no directory is not a device.
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return nil }
    let display = config["avd.ini.displayname"].flatMap { $0.isEmpty ? nil : $0 }
    return AvdInfo(
      name: name,
      displayName: display ?? name,
      directory: directory,
      target: values["target"] ?? config["target"],
      imageSysdir: config["image.sysdir.1"],
      tagId: config["tag.id"],
      abi: config["abi.type"],
      ramMb: config["hw.ramSize"].flatMap(Int.init),
      dataPartition: config["disk.dataPartition.size"])
  }
}
