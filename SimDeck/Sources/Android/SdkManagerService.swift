import Foundation

struct RemoteImage: Identifiable, Hashable {
  let packageId: String
  let size: String
  let api: Int
  let tag: String
  let abi: String

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
}

enum SdkManagerError: LocalizedError {
  case missing
  case javaMissing
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .missing:
      return "sdkmanager was not found in the Android SDK. Install the command-line tools."
    case .javaMissing:
      return "sdkmanager needs a Java runtime. Install one (brew install openjdk) and try again."
    case .failed(let message):
      return "sdkmanager failed. \(message)"
    }
  }
}

/// System image downloads through the SDK's own `sdkmanager`; uninstall is a
/// directory removal, so it also works without Java.
enum SdkManagerService {
  static var sdkManagerPath: String? {
    let root = ShellEnv.androidHome
    var candidates = [
      "\(root)/cmdline-tools/latest/bin/sdkmanager",
      "/opt/homebrew/bin/sdkmanager",
      "/usr/local/bin/sdkmanager",
      "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager",
    ]
    let tools = "\(root)/cmdline-tools"
    if let versions = try? FileManager.default.contentsOfDirectory(atPath: tools) {
      for version in versions {
        candidates.append("\(tools)/\(version)/bin/sdkmanager")
      }
    }
    return candidates.first(where: ShellEnv.exists)
  }

  static var javaHome: String? {
    let result = ProcessRunner.runSync("/usr/libexec/java_home", [])
    let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.ok && !path.isEmpty ? path : nil
  }

  static var javaAvailable: Bool { javaHome != nil }

  static var licensesAccepted: Bool {
    ShellEnv.exists("\(ShellEnv.androidHome)/licenses/android-sdk-license")
  }

  private static func environment() -> [String: String] {
    var env: [String: String] = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
    if let javaHome { env["JAVA_HOME"] = javaHome }
    return env
  }

  /// Downloadable system images from `sdkmanager --list`.
  static func availableImages() async -> [RemoteImage] {
    guard let sdk = sdkManagerPath else { return [] }
    let result = await ProcessRunner.run(
      sdk, ["--list"], timeout: 180, environment: environment())
    guard result.ok else { return [] }
    var seen: [String: RemoteImage] = [:]
    let separators = CharacterSet(charactersIn: "/;")
    for line in result.stdout.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      // Current sdkmanager prints `system-images/android-36/tag/abi  version
      // description`; older ones use `;` and a `|` size column.
      if let pipe = trimmed.firstIndex(of: "|") {
        let packageId = String(trimmed[..<pipe]).trimmingCharacters(in: .whitespaces)
        guard packageId.hasPrefix("system-images;") else { continue }
        let rest = String(trimmed[trimmed.index(after: pipe)...])
          .trimmingCharacters(in: .whitespaces)
        if let image = image(packageId: packageId, size: rest) { seen[packageId] = image }
        continue
      }
      guard trimmed.hasPrefix("system-images/") || trimmed.hasPrefix("system-images;")
      else { continue }
      let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
      guard let path = tokens.first else { continue }
      let parts = path.components(separatedBy: separators).filter { !$0.isEmpty }
      guard parts.count >= 4 else { continue }
      let apiText = parts[1].replacingOccurrences(of: "android-", with: "")
      guard let api = Int(apiText) else { continue }
      let packageId = "system-images;android-\(api);\(parts[2]);\(parts[3])"
      let description = tokens.dropFirst(2).joined(separator: " ")
      let size = tokens.count > 1 ? tokens[1] : ""
      seen[packageId] = RemoteImage(
        packageId: packageId,
        size: description.isEmpty ? size : description,
        api: api,
        tag: parts[2],
        abi: parts[3])
    }
    return seen.values.sorted {
      if $0.api != $1.api { return $0.api > $1.api }
      if $0.tag != $1.tag { return $0.tag < $1.tag }
      return $0.abi < $1.abi
    }
  }

  private static func image(packageId: String, size: String) -> RemoteImage? {
    let parts = packageId.split(separator: ";").map(String.init)
    guard parts.count >= 4, let apiText = parts[1].split(separator: "-").last,
      let api = Int(apiText)
    else { return nil }
    return RemoteImage(
      packageId: packageId, size: size, api: api, tag: parts[2], abi: parts[3])
  }

  static func install(
    _ packageId: String,
    onProgress: @escaping (Double, String) -> Void
  ) async throws {
    guard let sdk = sdkManagerPath else { throw SdkManagerError.missing }
    guard javaAvailable else { throw SdkManagerError.javaMissing }
    try await runStreaming(sdk, [packageId], onProgress: onProgress)
  }

  static func acceptLicenses(
    onProgress: @escaping (Double, String) -> Void
  ) async throws {
    guard let sdk = sdkManagerPath else { throw SdkManagerError.missing }
    guard javaAvailable else { throw SdkManagerError.javaMissing }
    try await runStreaming(sdk, ["--licenses"], onProgress: onProgress)
  }

  /// Removes an installed image's directory; the guard decides whether it
  /// may go.
  static func uninstall(_ packageId: String) throws {
    let parts = packageId.split(separator: ";").map(String.init)
    guard parts.count >= 4, parts[0] == "system-images" else {
      throw SdkManagerError.failed("Not a system image: \(packageId)")
    }
    let path = "\(ShellEnv.systemImagesRoot)/\(parts[1])/\(parts[2])/\(parts[3])"
    guard FileManager.default.fileExists(atPath: path) else { return }
    try FileManager.default.removeItem(atPath: path)
    // Drop the now-empty tag/API folders so the list stays clean.
    for parent in [
      "\(ShellEnv.systemImagesRoot)/\(parts[1])/\(parts[2])",
      "\(ShellEnv.systemImagesRoot)/\(parts[1])",
    ] {
      if let items = try? FileManager.default.contentsOfDirectory(atPath: parent),
        items.isEmpty
      {
        try? FileManager.default.removeItem(atPath: parent)
      }
    }
  }

  private static func runStreaming(
    _ executable: String,
    _ arguments: [String],
    onProgress: @escaping (Double, String) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.environment = environment()

      let inputPipe = Pipe()
      let outputPipe = Pipe()
      let errorPipe = Pipe()
      process.standardInput = inputPipe
      process.standardOutput = outputPipe
      process.standardError = errorPipe

      let handle: (Data) -> Void = { data in
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
          if let percent = percent(in: line) {
            onProgress(Double(percent) / 100, line)
          } else {
            onProgress(-1, line)
          }
        }
      }
      outputPipe.fileHandleForReading.readabilityHandler = { file in
        let data = file.availableData
        if data.isEmpty {
          file.readabilityHandler = nil
          return
        }
        handle(data)
      }
      errorPipe.fileHandleForReading.readabilityHandler = { file in
        let data = file.availableData
        if data.isEmpty {
          file.readabilityHandler = nil
          return
        }
        handle(data)
      }

      process.terminationHandler = { [inputPipe] finished in
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        _ = inputPipe
        DispatchQueue.main.async {
          if finished.terminationStatus == 0 {
            continuation.resume()
          } else {
            continuation.resume(
              throwing: SdkManagerError.failed(
                "exit status \(finished.terminationStatus)"))
          }
        }
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
        return
      }
      // Answer every licence prompt with yes.
      for _ in 0..<60 {
        try? inputPipe.fileHandleForWriting.write(contentsOf: Data("y\n".utf8))
      }
    }
  }

  private static func percent(in line: String) -> Int? {
    guard let range = line.range(of: #"(\d{1,3})%"#, options: .regularExpression) else {
      return nil
    }
    let digits = line[range].filter(\.isNumber)
    guard let value = Int(digits), value <= 100 else { return nil }
    return value
  }
}
