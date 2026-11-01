import CoreGraphics
import Foundation

enum ScrcpyError: LocalizedError {
  case server(String)
  case notReady

  var errorDescription: String? {
    switch self {
    case .server(let message): return message
    case .notReady: return "The stream is not ready yet."
    }
  }
}

/// Streams an Android device with the scrcpy server and injects input over
/// its control socket.
final class ScrcpySession: DeviceSession {
  static let remoteJar = "/data/local/tmp/scrcpy-server.jar"
  static let bundledVersion = "4.0"

  let deviceKey: String
  let serial: String
  let sink = VideoSink()
  var onStatusChange: ((SessionStatus) -> Void)?

  private let maxSize: Int
  private let bitRate: Int
  private let maxFps: Int
  private let decoder = H264Decoder()

  private let lock = NSLock()
  private var _status: SessionStatus = .connecting
  private var _size: CGSize = .zero
  private var videoFD: Int32 = -1
  private var controlFD: Int32 = -1
  private var forwardPort: UInt16 = 0
  private var socketName = ""
  private var serverProcess: Process?
  private var serverLog = ""
  private var running = false
  private var width = 0
  private var height = 0
  private var config: Data?
  private var lastKeyFrame: Date?
  private var pendingKeyFrame: DispatchWorkItem?

  init(
    deviceKey: String, serial: String, maxSize: Int = 1280,
    bitRate: Int = 8_000_000, maxFps: Int = 60
  ) {
    self.deviceKey = deviceKey
    self.serial = serial
    self.maxSize = maxSize
    self.bitRate = bitRate
    self.maxFps = maxFps
    decoder.onFrame = { [weak self] buffer in self?.sink.enqueue(buffer) }
  }

  deinit { stop() }

  var size: CGSize {
    lock.lock()
    defer { lock.unlock() }
    return _size
  }

  var status: SessionStatus {
    lock.lock()
    defer { lock.unlock() }
    return _status
  }

  var framesShown: Int { sink.framesShown }

  /// What the server printed; quoted when a session fails.
  var diagnosticLog: String {
    lock.lock()
    defer { lock.unlock() }
    return serverLog.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Whether the adb shell holding the scrcpy server is still alive.
  var isServerRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return serverProcess?.isRunning ?? false
  }

  // MARK: - Lifecycle

  func start() async throws {
    lock.lock()
    running = true
    lock.unlock()
    emit(.connecting)
    do {
      let jar = try Self.locateServer()
      try await prepareServer(jar: jar)
      try connectVideo()
      try connectControl()
      emitLive()
    } catch {
      stop()
      emit(.failed(error.localizedDescription))
      throw error
    }
  }

  func stop() {
    lock.lock()
    let wasActive = running || videoFD >= 0 || controlFD >= 0
    running = false
    let video = videoFD
    let control = controlFD
    let port = forwardPort
    videoFD = -1
    controlFD = -1
    pendingKeyFrame?.cancel()
    pendingKeyFrame = nil
    lock.unlock()

    guard wasActive else { return }
    if video >= 0 { shutdown(video, SHUT_RDWR); close(video) }
    if control >= 0 { shutdown(control, SHUT_RDWR); close(control) }
    serverProcess?.terminate()
    serverProcess = nil
    decoder.stop()
    if port != 0 {
      let serial = self.serial
      Task {
        _ = await ProcessRunner.run(
          ShellEnv.adbPath, ["-s", serial, "forward", "--remove", "tcp:\(port)"], timeout: 15)
      }
    }
  }

  private func prepareServer(jar: ServerJar) async throws {
    let adb = ShellEnv.adbPath
    let bootScript = #"while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done"#
    let boot = await ProcessRunner.run(
      adb, ["-s", serial, "shell", bootScript], timeout: 200)
    guard boot.ok else {
      throw ScrcpyError.server("The device did not finish booting. \(boot.combined)")
    }

    let push = await ProcessRunner.run(
      adb, ["-s", serial, "push", jar.path.path, Self.remoteJar], timeout: 120)
    guard push.ok else {
      throw ScrcpyError.server("adb push failed. \(push.combined)")
    }

    let scid = Int.random(in: 1...0x7fff_ffff)
    let hex = String(scid, radix: 16)
    socketName = "scrcpy_" + String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    let forward = await ProcessRunner.run(
      adb, ["-s", serial, "forward", "tcp:0", "localabstract:\(socketName)"], timeout: 30)
    let portText = forward.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard forward.ok, let port = UInt16(portText) else {
      throw ScrcpyError.server("adb forward failed. \(forward.combined)")
    }
    lock.lock()
    forwardPort = port
    lock.unlock()

    let arguments = [
      "-s", serial, "shell",
      "CLASSPATH=\(Self.remoteJar)",
      "app_process", "/", "com.genymobile.scrcpy.Server",
      jar.version,
      "scid=\(hex)",
      "log_level=warn",
      "tunnel_forward=true",
      "audio=false",
      "control=true",
      "send_device_meta=false",
      "max_size=\(maxSize)",
      "video_bit_rate=\(bitRate)",
      "max_fps=\(maxFps)",
      "video_codec_options=i-frame-interval:int=1",
      "stay_awake=true",
      "show_touches=false",
      "power_off_on_close=false",
    ]
    guard
      let process = ProcessRunner.launch(
        adb, arguments,
        onOutput: { [weak self] chunk in
          guard let self else { return }
          self.lock.lock()
          self.serverLog += chunk
          if self.serverLog.count > 8000 {
            self.serverLog = String(self.serverLog.suffix(4000))
          }
          self.lock.unlock()
        })
    else {
      throw ScrcpyError.server("Could not start the scrcpy server.")
    }
    lock.lock()
    serverProcess = process
    lock.unlock()
  }

  private func connectVideo() throws {
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
      do {
        let fd = try openVideoSocket()
        lock.lock()
        videoFD = fd
        lock.unlock()
        readVideo(fd: fd)
        return
      } catch {
        usleep(200_000)
      }
    }
    lock.lock()
    let log = serverLog
    lock.unlock()
    throw ScrcpyError.server(
      "Could not reach the scrcpy server. \(log.isEmpty ? "" : String(log.suffix(400)))")
  }

  /// adb's forward listener accepts a host connection before the device side
  /// exists, then closes it at once. The dummy byte only arrives once the
  /// server really took the video socket, so that is the readiness signal.
  private func openVideoSocket() throws -> Int32 {
    let fd = try connectSocket(deadline: 3)
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var byte: UInt8 = 0
    let count = recv(fd, &byte, 1, 0)
    guard count == 1 else {
      close(fd)
      throw ScrcpyError.notReady
    }
    var noTimeout = timeval(tv_sec: 0, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &noTimeout, socklen_t(MemoryLayout<timeval>.size))
    return fd
  }

  private func connectControl() throws {
    let fd = try connectSocket(deadline: 10)
    lock.lock()
    controlFD = fd
    lock.unlock()
  }

  private func connectSocket(deadline: TimeInterval) throws -> Int32 {
    let end = Date().addingTimeInterval(deadline)
    repeat {
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      if fd >= 0 {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = forwardPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
          pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
          }
        }
        if result == 0 { return fd }
        close(fd)
      }
      usleep(100_000)
    } while Date() < end
    lock.lock()
    let log = serverLog
    lock.unlock()
    throw ScrcpyError.server(
      "Could not reach the scrcpy server. \(log.isEmpty ? "" : String(log.suffix(400)))")
  }

  // MARK: - Video

  private func readVideo(fd: Int32) {
    let queue = DispatchQueue(label: "dev.simdeck.scrcpy.video", qos: .userInteractive)
    queue.async { [weak self] in
      guard let self else { return }
      var parser = ScrcpyVideoParser()
      var buffer = [UInt8](repeating: 0, count: 1 << 16)
      while self.isRunning {
        let count = recv(fd, &buffer, buffer.count, 0)
        if count <= 0 { break }
        let data = Data(bytes: buffer, count: count)
        for item in parser.add(data) { self.handle(item) }
      }
      close(fd)
      if self.isRunning {
        let log = self.diagnosticLog
        self.emit(
          .failed(
            log.isEmpty
              ? "The stream ended."
              : "The stream ended. \(String(log.suffix(400)))"))
      }
    }
  }

  private func handle(_ item: ScrcpyVideoItem) {
    switch item {
    case .session(let w, let h):
      guard w > 0, h > 0 else { return }
      lock.lock()
      width = w
      height = h
      _size = CGSize(width: w, height: h)
      lock.unlock()
      emitLive()
    case .packet(let packet):
      if packet.isConfig {
        config = packet.data
        return
      }
      var payload = packet.data
      if packet.isKeyFrame, let config, !config.isEmpty {
        var merged = Data(capacity: config.count + payload.count)
        merged.append(config)
        merged.append(payload)
        payload = merged
      }
      if decoder.decode(payload) { requestKeyFrame() }
    }
  }

  // MARK: - Input

  func touch(_ phase: TouchPhase, x: Double, y: Double) {
    lock.lock()
    let w = width
    let h = height
    let fd = controlFD
    lock.unlock()
    guard fd >= 0, w > 0, h > 0 else { return }
    let action: UInt8 = phase == .down ? 0 : (phase == .up ? 1 : 2)
    let px = Int32((min(max(x, 0), 1) * Double(w)).rounded())
    let py = Int32((min(max(y, 0), 1) * Double(h)).rounded())
    send(
      ScrcpyControl.touch(
        action: action, x: px, y: py,
        width: UInt16(clamping: w), height: UInt16(clamping: h)))
  }

  func press(_ button: DeviceButton) {
    let code: Int32
    switch button {
    case .back: code = Scrcpy.keyBack
    case .home: code = Scrcpy.keyHome
    case .recents: code = Scrcpy.keyAppSwitch
    case .lock: code = Scrcpy.keyPower
    case .volumeUp: code = Scrcpy.keyVolumeUp
    case .volumeDown: code = Scrcpy.keyVolumeDown
    }
    send(ScrcpyControl.keycode(action: 0, code: code))
    send(ScrcpyControl.keycode(action: 1, code: code))
  }

  func typeText(_ text: String) {
    guard !text.isEmpty else { return }
    send(ScrcpyControl.text(text))
  }

  func rotate() {
    send(ScrcpyControl.rotateDevice())
  }

  // MARK: - Plumbing

  private var isRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return running
  }

  private func send(_ data: Data) {
    lock.lock()
    let fd = controlFD
    lock.unlock()
    guard fd >= 0 else { return }
    data.withUnsafeBytes { raw in
      _ = Darwin.send(fd, raw.baseAddress, data.count, 0)
    }
  }

  private func emit(_ next: SessionStatus) {
    lock.lock()
    _status = next
    let handler = onStatusChange
    lock.unlock()
    handler?(next)
  }

  private func emitLive() {
    lock.lock()
    let ready = running && controlFD >= 0 && width > 0 && height > 0
    let already = _status == .live
    lock.unlock()
    if ready, !already { emit(.live) }
  }

  /// At most one request a second: each one restarts the encoder. A request
  /// inside the window is deferred, not dropped.
  private func requestKeyFrame() {
    lock.lock()
    guard running else {
      lock.unlock()
      return
    }
    if pendingKeyFrame != nil {
      lock.unlock()
      return
    }
    let elapsed = Date().timeIntervalSince(lastKeyFrame ?? .distantPast)
    let wait = max(0, 1.0 - elapsed)
    if wait <= 0 {
      lastKeyFrame = Date()
      let fd = controlFD
      lock.unlock()
      if fd >= 0 {
        ScrcpyControl.resetVideo().withUnsafeBytes { raw in
          _ = Darwin.send(fd, raw.baseAddress, 1, 0)
        }
      }
      return
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.pendingKeyFrame = nil
      guard self.running else {
        self.lock.unlock()
        return
      }
      self.lastKeyFrame = Date()
      let fd = self.controlFD
      self.lock.unlock()
      if fd >= 0 {
        ScrcpyControl.resetVideo().withUnsafeBytes { raw in
          _ = Darwin.send(fd, raw.baseAddress, 1, 0)
        }
      }
    }
    pendingKeyFrame = work
    lock.unlock()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + wait, execute: work)
  }

  // MARK: - Server discovery

  private struct ServerJar {
    let path: URL
    let version: String
  }

  private static func locateServer() throws -> ServerJar {
    if let custom = ShellEnv.environment["SCRCPY_SERVER_PATH"], ShellEnv.exists(custom) {
      return ServerJar(
        path: URL(fileURLWithPath: custom),
        version: versionNearServer(custom) ?? bundledVersion)
    }
    for candidate in [
      "/opt/homebrew/share/scrcpy/scrcpy-server",
      "/usr/local/share/scrcpy/scrcpy-server",
    ] where ShellEnv.exists(candidate) {
      return ServerJar(
        path: URL(fileURLWithPath: candidate),
        version: versionNearServer(candidate) ?? bundledVersion)
    }
    if let bundled = Bundle.main.url(forResource: "scrcpy-server", withExtension: nil) {
      return ServerJar(path: bundled, version: bundledVersion)
    }
    throw ScrcpyError.server(
      "scrcpy-server not found. Install scrcpy (brew install scrcpy) or set SCRCPY_SERVER_PATH.")
  }

  private static func versionNearServer(_ path: String) -> String? {
    let prefix = URL(fileURLWithPath: path)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let binary = prefix.appendingPathComponent("bin/scrcpy").path
    guard ShellEnv.exists(binary) else { return nil }
    let result = ProcessRunner.runSync(binary, ["--version"], timeout: 10)
    guard result.ok else { return nil }
    for token in result.stdout.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "v" }) {
      let text = String(token)
      if text.first?.isNumber == true, text.contains(".") { return text }
    }
    return nil
  }
}
