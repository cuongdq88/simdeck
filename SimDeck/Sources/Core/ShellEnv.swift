import Foundation

/// Paths and environment lookups shared by every service.
enum ShellEnv {
  static var environment: [String: String] { ProcessInfo.processInfo.environment }
  static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

  static func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  /// `ANDROID_HOME`, else `ANDROID_SDK_ROOT`, else the two common macOS installs.
  static var androidHome: String {
    for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
      if let value = environment[key], !value.isEmpty { return value }
    }
    let candidates = [
      "\(home)/Library/Android/sdk",
      "/opt/homebrew/share/android-commandlinetools",
    ]
    return candidates.first(where: exists) ?? "\(home)/Library/Android/sdk"
  }

  /// `ANDROID_AVD_HOME`, else `ANDROID_USER_HOME/avd`, else `~/.android/avd`.
  static var avdHome: String {
    if let value = environment["ANDROID_AVD_HOME"], !value.isEmpty { return value }
    if let value = environment["ANDROID_USER_HOME"], !value.isEmpty { return "\(value)/avd" }
    return "\(home)/.android/avd"
  }

  /// GUI apps do not inherit the shell PATH, so probe the usual places.
  static var adbPath: String {
    let candidates = [
      "\(androidHome)/platform-tools/adb",
      "/opt/homebrew/bin/adb",
      "/usr/local/bin/adb",
    ]
    return candidates.first(where: exists) ?? "adb"
  }

  static var emulatorPath: String { "\(androidHome)/emulator/emulator" }

  static var systemImagesRoot: String { "\(androidHome)/system-images" }

  static var developerDir: String {
    let fallback = "/Applications/Xcode.app/Contents/Developer"
    let result = ProcessRunner.runSync("/usr/bin/xcode-select", ["-p"])
    let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.ok && !path.isEmpty ? path : fallback
  }

  /// Free bytes on the volume holding [url]'s nearest existing ancestor.
  static func freeDiskBytes(at url: URL) -> Int64 {
    var probe = url
    while !exists(probe.path) && probe.path != "/" {
      probe.deleteLastPathComponent()
    }
    let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    if let capacity = values?.volumeAvailableCapacityForImportantUsage { return capacity }
    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: probe.path)
    return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
  }
}
