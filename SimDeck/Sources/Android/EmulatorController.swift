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

  /// Boots [name]; [headless] keeps the emulator window out of the way.
  func start(name: String, headless: Bool) throws {
    guard emulatorAvailable else { throw EmulatorError.binaryMissing(ShellEnv.emulatorPath) }
    if processes[name]?.isRunning == true { throw EmulatorError.alreadyRunning }

    var arguments = ["@\(name)"]
    if headless {
      arguments += ["-no-window", "-no-boot-anim", "-gpu", "host"]
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
    if let serial {
      _ = await AdbService.kill(serial: serial)
    }
    if let process = processes[name], process.isRunning {
      process.terminate()
    }
    processes[name] = nil
  }

  func lastLog(for name: String) -> String {
    logs[name, default: ""]
  }

  func forget(name: String) {
    processes[name] = nil
    logs[name] = nil
  }
}
