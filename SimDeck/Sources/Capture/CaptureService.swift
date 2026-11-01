import Foundation

enum CaptureError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}

/// Screenshots and screen recordings, saved next to each other.
enum CaptureService {
  struct ActiveRecording {
    let started: Date
    let localURL: URL
    let remotePath: String?
    let process: Process?
  }

  static var directory: URL {
    let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    let folder = base.appendingPathComponent("SimDeck", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true)
    return folder
  }

  static func stamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    return formatter.string(from: Date())
  }

  static func screenshot(_ device: Device) async throws -> URL {
    let url = directory.appendingPathComponent("\(safe(device.name))-\(stamp()).png")
    switch device.os {
    case .android:
      guard let serial = device.serial else {
        throw CaptureError.message("Start the device before taking a screenshot.")
      }
      let result = await ProcessRunner.runData(
        ShellEnv.adbPath, ["-s", serial, "exec-out", "screencap", "-p"], timeout: 30)
      guard result.status == 0, !result.data.isEmpty else {
        throw CaptureError.message(
          "screencap failed. \(String(data: result.data, encoding: .utf8) ?? result.stderr)")
      }
      try result.data.write(to: url, options: .atomic)
    case .ios:
      let result = await ProcessRunner.run(
        "/usr/bin/xcrun",
        ["simctl", "io", device.rawID, "screenshot", url.path], timeout: 30)
      guard result.ok else {
        throw CaptureError.message("simctl screenshot failed. \(result.combined)")
      }
    }
    return url
  }

  static func startRecording(_ device: Device) async throws -> ActiveRecording {
    let url = directory.appendingPathComponent("\(safe(device.name))-\(stamp()).mp4")
    switch device.os {
    case .android:
      guard let serial = device.serial else {
        throw CaptureError.message("Start the device before recording it.")
      }
      let remote = "/sdcard/simdeck-\(stamp()).mp4"
      let process = ProcessRunner.launch(
        ShellEnv.adbPath,
        ["-s", serial, "shell", "screenrecord", "--bit-rate", "8000000",
         "--time-limit", "180", remote])
      guard process != nil else {
        throw CaptureError.message("Could not start screenrecord.")
      }
      return ActiveRecording(
        started: Date(), localURL: url, remotePath: remote, process: process)
    case .ios:
      let process = ProcessRunner.launch(
        "/usr/bin/xcrun",
        ["simctl", "io", device.rawID, "recordVideo", "--codec=h264", url.path])
      guard process != nil else {
        throw CaptureError.message("Could not start simctl recordVideo.")
      }
      return ActiveRecording(
        started: Date(), localURL: url, remotePath: nil, process: process)
    }
  }

  static func stopRecording(_ device: Device, recording: ActiveRecording) async -> URL? {
    switch device.os {
    case .android:
      guard let serial = device.serial, let remote = recording.remotePath else {
        recording.process?.terminate()
        return nil
      }
      _ = await ProcessRunner.run(
        ShellEnv.adbPath, ["-s", serial, "shell", "pkill", "-INT", "screenrecord"],
        timeout: 15)
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      _ = await ProcessRunner.runData(
        ShellEnv.adbPath,
        ["-s", serial, "pull", remote, recording.localURL.path], timeout: 120)
      _ = await ProcessRunner.run(
        ShellEnv.adbPath, ["-s", serial, "shell", "rm", "-f", remote], timeout: 15)
      recording.process?.terminate()
    case .ios:
      if let process = recording.process, process.isRunning {
        kill(process.processIdentifier, SIGINT)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if process.isRunning { process.terminate() }
      }
    }
    let exists = FileManager.default.fileExists(atPath: recording.localURL.path)
    return exists ? recording.localURL : nil
  }

  private static func safe(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    return name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("")
      { $0 + String($1) }
  }
}
