import Foundation

/// One installed Android system image, found by scanning the SDK, so no
/// `sdkmanager` (and no Java runtime) is needed to list what can boot.
struct SystemImage: Identifiable, Hashable {
  let packageId: String
  let api: Int
  let tag: String
  let abi: String
  let path: URL

  var id: String { packageId }

  var tagLabel: String {
    switch tag {
    case "google_apis": return "Google APIs"
    case "google_apis_playstore": return "Google Play"
    case "default": return "AOSP"
    case "aosp_atd": return "AOSP ATD"
    case "google_atd": return "Google ATD"
    default: return tag.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  var label: String { "API \(api) · \(tagLabel) · \(abi)" }

  var sysdir: String {
    "system-images/android-\(api)/\(tag)/\(abi)/"
  }
}

enum SystemImages {
  /// Scans `$ANDROID_HOME/system-images/android-<api>/<tag>/<abi>/`.
  static func installed() -> [SystemImage] {
    let root = URL(fileURLWithPath: ShellEnv.systemImagesRoot, isDirectory: true)
    let fileManager = FileManager.default
    guard
      let apiDirs = try? fileManager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey])
    else { return [] }

    var images: [SystemImage] = []
    for apiDir in apiDirs where apiDir.lastPathComponent.hasPrefix("android-") {
      guard
        let api = Int(apiDir.lastPathComponent.dropFirst("android-".count)),
        let tags = try? fileManager.contentsOfDirectory(
          at: apiDir, includingPropertiesForKeys: [.isDirectoryKey])
      else { continue }
      for tagDir in tags {
        guard
          let abis = try? fileManager.contentsOfDirectory(
            at: tagDir, includingPropertiesForKeys: [.isDirectoryKey])
        else { continue }
        for abiDir in abis {
          let path = abiDir
          guard isComplete(path) else { continue }
          images.append(
            SystemImage(
              packageId: "system-images;android-\(api);\(tagDir.lastPathComponent);\(abiDir.lastPathComponent)",
              api: api,
              tag: tagDir.lastPathComponent,
              abi: abiDir.lastPathComponent,
              path: path))
        }
      }
    }
    return images.sorted {
      if $0.api != $1.api { return $0.api > $1.api }
      if $0.tag != $1.tag { return $0.tag < $1.tag }
      return $0.abi < $1.abi
    }
  }

  /// The emulator needs the system partition; a half-downloaded image only
  /// has a directory.
  private static func isComplete(_ url: URL) -> Bool {
    let fileManager = FileManager.default
    let markers = ["system.img", "system.img.qcow2", "ramdisk.img", "package.xml"]
    return markers.contains {
      fileManager.fileExists(atPath: url.appendingPathComponent($0).path)
    }
      && !fileManager.fileExists(atPath: url.appendingPathComponent(".downloadInterrupted").path)
  }

  /// ABI choices for this Mac: Apple Silicon runs arm64 images.
  static var hostABIs: [String] {
    #if arch(arm64)
      return ["arm64-v8a", "x86_64"]
    #else
      return ["x86_64", "arm64-v8a"]
    #endif
  }

  static func defaultABI(for images: [SystemImage]) -> String? {
    for abi in hostABIs {
      if images.contains(where: { $0.abi == abi }) { return abi }
    }
    return images.first?.abi
  }
}
