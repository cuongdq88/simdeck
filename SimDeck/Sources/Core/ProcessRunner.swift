import Foundation

struct ProcessResult {
  let status: Int32
  let stdout: String
  let stderr: String

  var ok: Bool { status == 0 }

  var combined: String {
    [stdout, stderr]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }
}

/// Runs command-line tools without a shell, so arguments are never parsed.
enum ProcessRunner {
  /// `Process` does not keep `standardInput` alive, and an idle pipe is what
  /// keeps `adb shell` from seeing EOF and killing a long-running server.
  private static let inputLock = NSLock()
  private static var openInputs: [Pipe] = []

  /// Runs to completion and collects stdout/stderr, off the caller's thread.
  static func run(
    _ executable: String,
    _ arguments: [String] = [],
    timeout: TimeInterval = 60,
    stdin: Data? = nil,
    environment: [String: String]? = nil
  ) async -> ProcessResult {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(
          returning: runSync(
            executable, arguments, timeout: timeout, stdin: stdin, environment: environment))
      }
    }
  }

  static func runSync(
    _ executable: String,
    _ arguments: [String] = [],
    timeout: TimeInterval = 60,
    stdin: Data? = nil,
    environment: [String: String]? = nil
  ) -> ProcessResult {
    let process = Process()
    if executable.contains("/") {
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [executable] + arguments
    }
    if let environment {
      var env = ProcessInfo.processInfo.environment
      env.merge(environment) { _, new in new }
      process.environment = env
    }

    let outPipe = Pipe()
    let errPipe = Pipe()
    let inPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe

    do {
      try process.run()
    } catch {
      return ProcessResult(status: -1, stdout: "", stderr: error.localizedDescription)
    }

    // The parent must drop its write ends or readDataToEndOfFile never sees EOF.
    try? outPipe.fileHandleForWriting.close()
    try? errPipe.fileHandleForWriting.close()
    if let stdin {
      inPipe.fileHandleForWriting.write(stdin)
      try? inPipe.fileHandleForWriting.close()
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var outData = Data()
    var errData = Data()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      let data = outPipe.fileHandleForReading.readDataToEndOfFile()
      lock.lock()
      outData = data
      lock.unlock()
      group.leave()
    }
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      let data = errPipe.fileHandleForReading.readDataToEndOfFile()
      lock.lock()
      errData = data
      lock.unlock()
      group.leave()
    }

    let deadline = DispatchWorkItem {
      if process.isRunning { process.terminate() }
    }
    if timeout > 0 {
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
    }
    process.waitUntilExit()
    deadline.cancel()
    group.wait()

    lock.lock()
    let out = outData
    let err = errData
    lock.unlock()
    return ProcessResult(
      status: process.terminationStatus,
      stdout: String(decoding: out, as: UTF8.self),
      stderr: String(decoding: err, as: UTF8.self))
  }

  /// Starts a long-running tool and returns immediately.
  @discardableResult
  static func launch(
    _ executable: String,
    _ arguments: [String],
    environment: [String: String]? = nil,
    onOutput: ((String) -> Void)? = nil
  ) -> Process? {
    let process = Process()
    if executable.contains("/") {
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [executable] + arguments
    }
    if let environment {
      var env = ProcessInfo.processInfo.environment
      env.merge(environment) { _, new in new }
      process.environment = env
    }
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    // `adb shell` forwards stdin and tears the remote shell down on EOF, which
    // kills a long-running server before it accepts a socket. An idle pipe,
    // retained here, keeps stdin open for the process's lifetime.
    let inputPipe = Pipe()
    process.standardInput = inputPipe
    inputLock.lock()
    openInputs.append(inputPipe)
    inputLock.unlock()
    process.terminationHandler = { _ in
      inputLock.lock()
      openInputs.removeAll { $0 === inputPipe }
      inputLock.unlock()
    }
    if let onOutput {
      let emit: (FileHandle) -> Void = { handle in
        handle.readabilityHandler = { h in
          let data = h.availableData
          if data.isEmpty {
            h.readabilityHandler = nil
            return
          }
          onOutput(String(decoding: data, as: UTF8.self))
        }
      }
      emit(outPipe.fileHandleForReading)
      emit(errPipe.fileHandleForReading)
    }
    do {
      try process.run()
      return process
    } catch {
      return nil
    }
  }
}
