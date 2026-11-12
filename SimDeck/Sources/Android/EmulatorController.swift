import Foundation

enum EmulatorError: LocalizedError {
  case binaryMissing(String)
  case launchFailed(String)
  case bootTimedOut(String)
  case alreadyRunning

  var errorDescription: String? {
    switch self {
    case .binaryMissing(let path):
      return "The Android emulator was not found at \(path). Install the SDK emulator package."
    case .launchFailed(let message):
      return "Could not start the emulator: \(message)"
    case .bootTimedOut(let name):
      return "\(name) did not come online. Check the AVD and the system image."
    case .alreadyRunning:
      return "This device is already running."
    }
  }
}

@MainActor
final class EmulatorController {
  private var processes: [String: Process] = [:]
  private var logs: [String: String] = [:]

  var emulatorAvailable: Bool { ShellEnv.exists(ShellEnv.emulatorPath) }

  /// Boots [name]; [headless] keeps the emulator window out of the way,
  /// [coldBoot] ignores a saved snapshot, and [cameraBack]/[cameraFront]
  /// override the AVD's camera sources.
  func start(
    name: String, headless: Bool, coldBoot: Bool = false,
    cameraBack: String? = nil, cameraFront: String? = nil
  ) throws {
    guard emulatorAvailable else { throw EmulatorError.binaryMissing(ShellEnv.emulatorPath) }
    if processes[name]?.isRunning == true { throw EmulatorError.alreadyRunning }

    // The tile plays the device's audio, so the emulator itself stays silent.
    var arguments = ["@\(name)", "-no-audio"]
    if headless {
      arguments += ["-no-window", "-no-boot-anim", "-gpu", "host"]
    }
    if coldBoot {
      arguments.append("-no-snapshot-load")
    }
    if let cameraBack, !cameraBack.isEmpty {
      arguments += ["-camera-back", cameraBack]
    }
    if let cameraFront, !cameraFront.isEmpty {
      arguments += ["-camera-front", cameraFront]
    }
    let process = ProcessRunner.launch(
      ShellEnv.emulatorPath, arguments,
      onOutput: { [weak self] chunk in
        Task { @MainActor in
          guard let self else { return }
          self.logs[name, default: ""] += chunk
          if self.logs[name, default: ""].count > 8000 {
            self.logs[name] = String(self.logs[name, default: ""].suffix(4000))
          }
        }
      })
    guard let process else { throw EmulatorError.launchFailed("the emulator did not start") }
    processes[name] = process
  }

  /// Polls adb until the AVD's emulator registers, then returns its serial.
  func waitForSerial(avdName: String, timeout: TimeInterval = 180) async -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if processes[avdName]?.isRunning == false { return nil }
      let entries = await AdbService.devices()
      for entry in entries
      where entry.serial.hasPrefix("emulator-") && entry.isReady {
        if await AdbService.avdName(serial: entry.serial) == avdName {
          return entry.serial
        }
      }
      try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    return nil
  }

  func stop(name: String, serial: String?) async {
    // adb may have lost the emulator (a stale server, a crashed window)
    // while qemu keeps running; ask adb again, then fall back to the process.
    let running = await AdbService.runningAvds()
    if let current = running[name] ?? serial {
      _ = await AdbService.kill(serial: current)
    }
    if let process = processes[name], process.isRunning {
      process.terminate()
    }
    processes[name] = nil
    await Self.terminateProcesses(forAVD: name)
  }

  /// qemu processes that belong to [avdName], found by command line. Covers
  /// emulators started by an earlier app session or another tool.
  nonisolated static func runningAVDProcesses() async -> [String: Int32] {
    let result = await ProcessRunner.run(
      "/bin/ps", ["-axo", "pid=,command="], timeout: 10)
    guard result.ok else { return [:] }
    var map: [String: Int32] = [:]
    for line in result.stdout.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.contains("qemu-system") else { continue }
      let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
      guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
      let command = parts[1]
      if let range = command.range(
        of: #"-avd\s+(\S+)"#, options: .regularExpression)
      {
        let name = command[range].split(separator: " ").last.map(String.init) ?? ""
        if !name.isEmpty { map[name] = pid }
      } else if let range = command.range(of: #"@(\S+)"#, options: .regularExpression) {
        map[String(command[range].dropFirst())] = pid
      }
    }
    return map
  }

  nonisolated static func avdProcesses(name: String) async -> [Int32] {
    let all = await runningAVDProcesses()
    return all[name].map { [$0] } ?? []
  }

  /// Host cameras the emulator can use, from `emulator -webcam-list`.
  nonisolated static func listWebcams() async -> [String] {
    guard ShellEnv.exists(ShellEnv.emulatorPath) else { return [] }
    let result = await ProcessRunner.run(
      ShellEnv.emulatorPath, ["-webcam-list"], timeout: 20)
    guard result.ok else { return [] }
    let pattern = #"Camera '(webcam\d+)' is connected"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(result.stdout.startIndex..., in: result.stdout)
    return expression.matches(in: result.stdout, range: range).compactMap { match in
      guard let found = Range(match.range(at: 1), in: result.stdout) else { return nil }
      return String(result.stdout[found])
    }
  }

  /// Escalates TERM to KILL so a wedged qemu cannot keep running unseen.
  nonisolated static func terminateProcesses(forAVD name: String) async {
    var pids = await avdProcesses(name: name)
    guard !pids.isEmpty else { return }
    for pid in pids { kill(pid, SIGTERM) }
    for _ in 0..<8 {
      try? await Task.sleep(nanoseconds: 400_000_000)
      pids = await avdProcesses(name: name)
      if pids.isEmpty { return }
    }
    for pid in pids { kill(pid, SIGKILL) }
    try? await Task.sleep(nanoseconds: 300_000_000)
  }

  func lastLog(for name: String) -> String {
    logs[name, default: ""]
  }

  func forget(name: String) {
    processes[name] = nil
    logs[name] = nil
  }
}
