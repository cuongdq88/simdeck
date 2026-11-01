import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var devices: [Device] = []
  @Published private(set) var sessions: [String: DeviceSession] = [:]
  /// Streams shown in the grid, in the order they were opened.
  @Published private(set) var openKeys: [String] = []
  @Published private(set) var fps: [String: Double] = [:]
  @Published private(set) var busy: Set<String> = []
  @Published private(set) var sessionErrors: [String: String] = [:]
  @Published private(set) var images: [SystemImage] = []
  @Published private(set) var androidHome = ""
  @Published private(set) var showFrames: [String: Bool] = [:]
  @Published private(set) var recordingStarts: [String: Date] = [:]
  @Published private(set) var remoteImages: [RemoteImage] = []
  @Published private(set) var installing: Set<String> = []
  @Published private(set) var installProgress: [String: Double] = [:]
  @Published private(set) var installMessage: [String: String] = [:]
  @Published private(set) var loadingRemoteImages = false
  @Published private(set) var tick = 0
  @Published private(set) var mcpRunning = false
  @Published private(set) var mcpError: String?
  @Published private(set) var mcpURL = ""
  @Published var errorMessage: String?
  @Published var notice: String?
  @Published var createSheetShown = false
  @Published var sdkSheetShown = false
  @Published var createPlatform = 0

  private let emulator = EmulatorController()
  private var loop: Task<Void, Never>?
  private var fpsSamples: [String: (count: Int, time: Date)] = [:]
  private var misses: [String: Int] = [:]
  private var recordings: [String: CaptureService.ActiveRecording] = [:]
  private var mcpServer: McpServer?

  var runningDevices: [Device] { devices.filter(\.isRunning) }
  var androidDevices: [Device] {
    devices.filter { $0.os == .android && $0.kind == .physical }
  }
  var iosSimulators: [Device] { devices.filter { $0.os == .ios } }

  /// The devices whose streams are open, in grid order.
  var openDevices: [Device] {
    openKeys.compactMap { key in devices.first { $0.key == key } }
  }

  var emulatorAvailable: Bool { ShellEnv.exists(ShellEnv.emulatorPath) }
  var adbAvailable: Bool { ShellEnv.exists(ShellEnv.adbPath) }

  // MARK: - Lifecycle

  func start() async {
    androidHome = ShellEnv.androidHome
    await reloadImages()
    await refresh()
    if let flag = ProcessInfo.processInfo.environment["SIMDECK_OPEN_STREAMS"],
      flag == "1" || flag == "first"
    {
      let running = devices.filter(\.isRunning)
      let targets = flag == "first" ? Array(running.prefix(1)) : running
      for device in targets {
        await openStream(device)
      }
    }
    guard loop == nil else { return }
    startMcp()
    if ProcessInfo.processInfo.environment["SIMDECK_SHOW_SDK"] == "1" {
      sdkSheetShown = true
    }
    loop = Task { [weak self] in
      var ticks = 0
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let self else { return }
        self.measureFPS()
        self.tick &+= 1
        ticks += 1
        if ticks % 3 == 0 { await self.refresh() }
      }
    }
  }

  func reloadImages() async {
    images = await Task.detached(priority: .utility) { SystemImages.installed() }.value
  }

  // MARK: - MCP

  private func startMcp() {
    guard mcpServer == nil else { return }
    let port = UInt16(ProcessInfo.processInfo.environment["SIMDECK_MCP_PORT"] ?? "") ?? 8765
    let server = McpServer(model: self, port: port)
    mcpURL = server.url
    server.onChange = { [weak self, weak server] in
      guard let self, let server else { return }
      self.mcpRunning = server.running
      self.mcpError = server.error
    }
    server.start()
    mcpServer = server
  }

  // MARK: - Device list

  func refresh() async {
    async let simulators = Self.loadAndroidSimulators()
    async let android = Self.loadAndroidDevices()
    async let ios = SimctlService.listDevices()
    devices = await (simulators + android + ios)
    openKeys.removeAll { key in !devices.contains { $0.key == key } }
    pruneSessions()
  }

  private static func loadAndroidSimulators() async -> [Device] {
    async let serials = AdbService.runningAvds()
    async let processes = EmulatorController.runningAVDProcesses()
    let (running, qemu) = await (serials, processes)
    return AvdStore.list().map { avd in
      let serial = running[avd.name]
      let alive = serial != nil || qemu[avd.name] != nil
      return Device(
        key: "android:\(avd.name)",
        rawID: avd.name,
        name: avd.name,
        os: .android,
        kind: .simulator,
        platform: avd.platform,
        state: alive ? .booted : .shutdown,
        serial: serial,
        avdName: avd.name)
    }
  }

  private static func loadAndroidDevices() async -> [Device] {
    let entries = await AdbService.devices()
    return entries
      .filter { !$0.serial.hasPrefix("emulator-") }
      .map { entry in
        Device(
          key: "android:\(entry.serial)",
          rawID: entry.serial,
          name: entry.serial,
          os: .android,
          kind: .physical,
          platform: entry.isReady ? "Android device" : entry.state,
          state: entry.isReady ? .booted : .booting,
          serial: entry.serial,
          avdName: nil)
      }
  }

  private func pruneSessions() {
    for (key, session) in sessions {
      let running = devices.first { $0.key == key }?.isRunning ?? false
      if running {
        misses[key] = 0
        continue
      }
      let count = (misses[key] ?? 0) + 1
      misses[key] = count
      if count >= 2 {
        session.stop()
        sessions[key] = nil
        openKeys.removeAll { $0 == key }
        fps[key] = nil
        sessionErrors[key] = nil
        misses[key] = nil
      }
    }
  }

  // MARK: - Actions

  func start(_ device: Device) async {
    guard !busy.contains(device.key) else { return }
    busy.insert(device.key)
    defer { busy.remove(device.key) }
    do {
      switch device.os {
      case .android:
        if device.kind == .simulator {
          let name = device.avdName ?? device.rawID
          try emulator.start(name: name, headless: true)
          guard let serial = await emulator.waitForSerial(avdName: name) else {
            throw EmulatorError.bootTimedOut(name)
          }
          try await attachScrcpy(device: device, serial: serial)
        } else if let serial = device.serial {
          try await attachScrcpy(device: device, serial: serial)
        }
      case .ios:
        guard await SimctlService.boot(udid: device.rawID) else {
          throw SimulatorError("Could not boot \(device.name).")
        }
        try await attachSimulator(device)
      }
      if !openKeys.contains(device.key) { openKeys.append(device.key) }
      sessionErrors[device.key] = nil
      await refresh()
    } catch {
      sessionErrors[device.key] = error.localizedDescription
      errorMessage = error.localizedDescription
    }
  }

  func openStream(_ device: Device) async {
    guard sessions[device.key] == nil, !busy.contains(device.key) else { return }
    busy.insert(device.key)
    defer { busy.remove(device.key) }
    do {
      switch device.os {
      case .android:
        guard let serial = device.serial else {
          throw ScrcpyError.server("Start the device before streaming it.")
        }
        try await attachScrcpy(device: device, serial: serial)
      case .ios:
        guard device.isRunning else {
          throw SimulatorError("Boot the simulator before streaming it.")
        }
        try await attachSimulator(device)
      }
      if !openKeys.contains(device.key) { openKeys.append(device.key) }
      sessionErrors[device.key] = nil
    } catch {
      sessionErrors[device.key] = error.localizedDescription
      errorMessage = error.localizedDescription
    }
  }

  func closeStream(_ device: Device) {
    sessions[device.key]?.stop()
    sessions[device.key] = nil
    openKeys.removeAll { $0 == device.key }
    fps[device.key] = nil
    sessionErrors[device.key] = nil
  }

  func stop(_ device: Device) async {
    guard !busy.contains(device.key) else { return }
    busy.insert(device.key)
    defer { busy.remove(device.key) }
    closeStream(device)
    switch device.os {
    case .android:
      if device.kind == .simulator {
        let name = device.avdName ?? device.rawID
        await emulator.stop(name: name, serial: device.serial)
        emulator.forget(name: name)
      } else if let serial = device.serial {
        _ = await AdbService.kill(serial: serial)
      }
    case .ios:
      _ = await SimctlService.shutdown(udid: device.rawID)
    }
    await refresh()
    // The emulator needs a moment to drop off adb; refresh again so the row
    // does not linger in RUNNING.
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    await refresh()
  }

  func delete(_ device: Device) async {
    do {
      guard !device.isRunning else {
        throw GuardIssue(
          code: "device_running", message: "Stop \(device.name) before deleting it.")
      }
      switch device.os {
      case .android:
        guard device.kind == .simulator else {
          throw GuardIssue(
            code: "unsupported", message: "A physical device is removed by unplugging it.")
        }
        let running = Set(await AdbService.runningAvds().keys)
        if let issue = DeletionGuard.checkAvd(name: device.rawID, running: running) {
          throw issue
        }
        try AvdStore.delete(name: device.rawID)
      case .ios:
        guard await SimctlService.delete(udid: device.rawID) else {
          throw SimulatorError("simctl delete failed for \(device.name).")
        }
      }
      closeStream(device)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func wipe(_ device: Device) async {
    do {
      guard !busy.contains(device.key) else { return }
      busy.insert(device.key)
      defer { busy.remove(device.key) }
      switch device.os {
      case .android:
        guard device.kind == .simulator else { return }
        let running = Set(await AdbService.runningAvds().keys)
        if let issue = DeletionGuard.checkAvd(name: device.rawID, running: running) {
          throw issue
        }
        try AvdStore.wipe(name: device.rawID)
      case .ios:
        if device.isRunning {
          closeStream(device)
          _ = await SimctlService.shutdown(udid: device.rawID)
        }
        guard await SimctlService.erase(udid: device.rawID) else {
          throw SimulatorError("simctl erase failed for \(device.name).")
        }
      }
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func createAndroid(_ form: AvdCreateForm) async throws {
    let existing = Set(AvdStore.list().map(\.name))
    _ = try AvdCreator.create(form, existing: existing)
    await refresh()
  }

  func createSimulator(name: String, deviceTypeID: String, runtimeID: String) async throws {
    let result = await SimctlService.create(
      name: name, deviceTypeID: deviceTypeID, runtimeID: runtimeID)
    switch result {
    case .success:
      await refresh()
    case .failure(let error):
      throw error
    }
  }

  func session(for device: Device) -> DeviceSession? { sessions[device.key] }
  func fps(for device: Device) -> Double { fps[device.key] ?? 0 }
  func isBusy(_ device: Device) -> Bool { busy.contains(device.key) }
  func isStreaming(_ device: Device) -> Bool { sessions[device.key] != nil }
  func showFrame(_ device: Device) -> Bool { showFrames[device.key] ?? true }

  func toggleFrame(_ device: Device) {
    showFrames[device.key] = !showFrame(device)
  }

  func retry(_ device: Device) async {
    closeStream(device)
    await openStream(device)
  }

  // MARK: - Capture

  func takeScreenshot(_ device: Device) async {
    do {
      let url = try await CaptureService.screenshot(device)
      showNotice("Screenshot saved to \(url.lastPathComponent)")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func isRecording(_ device: Device) -> Bool { recordingStarts[device.key] != nil }

  func recordingStart(_ device: Device) -> Date? { recordingStarts[device.key] }

  func toggleRecording(_ device: Device) async {
    if let active = recordings.removeValue(forKey: device.key) {
      recordingStarts[device.key] = nil
      if let url = await CaptureService.stopRecording(device, recording: active) {
        showNotice("Recording saved to \(url.lastPathComponent)")
      }
    } else {
      do {
        let active = try await CaptureService.startRecording(device)
        recordings[device.key] = active
        recordingStarts[device.key] = active.started
        showNotice("Recording \(device.name)…")
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func showNotice(_ text: String) {
    notice = text
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_600_000_000)
      guard let self else { return }
      if self.notice == text { self.notice = nil }
    }
  }

  // MARK: - SDK Manager

  func loadRemoteImages() async {
    guard !loadingRemoteImages else { return }
    loadingRemoteImages = true
    remoteImages = await SdkManagerService.availableImages()
    loadingRemoteImages = false
  }

  func installImage(_ packageId: String) async {
    guard !installing.contains(packageId) else { return }
    installing.insert(packageId)
    installProgress[packageId] = 0
    installMessage[packageId] = "Starting…"
    do {
      try await SdkManagerService.install(packageId) { [weak self] progress, message in
        DispatchQueue.main.async {
          guard let self else { return }
          if progress >= 0 { self.installProgress[packageId] = progress }
          let text = message.trimmingCharacters(in: .whitespaces)
          if !text.isEmpty { self.installMessage[packageId] = text }
        }
      }
      installing.remove(packageId)
      installProgress[packageId] = nil
      installMessage[packageId] = nil
      showNotice("Installed \(packageId)")
      await reloadImages()
      remoteImages.removeAll { $0.packageId == packageId }
    } catch {
      installing.remove(packageId)
      installProgress[packageId] = nil
      installMessage[packageId] = nil
      errorMessage = error.localizedDescription
    }
  }

  func uninstallImage(_ packageId: String) async {
    do {
      if let issue = DeletionGuard.checkImage(packageId: packageId) { throw issue }
      try SdkManagerService.uninstall(packageId)
      await reloadImages()
      showNotice("Removed \(packageId)")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func acceptLicenses() async {
    do {
      try await SdkManagerService.acceptLicenses { [weak self] _, message in
        DispatchQueue.main.async {
          let text = message.trimmingCharacters(in: .whitespaces)
          if !text.isEmpty { self?.installMessage["licenses"] = text }
        }
      }
      installMessage["licenses"] = nil
      showNotice("Licences accepted")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Sessions

  private func attachScrcpy(device: Device, serial: String) async throws {
    let session = ScrcpySession(deviceKey: device.key, serial: serial)
    session.onStatusChange = { [weak self] status in
      DispatchQueue.main.async { self?.apply(status, key: device.key) }
    }
    sessions[device.key] = session
    do {
      try await Task.detached(priority: .userInitiated) {
        try await session.start()
      }.value
    } catch {
      sessions[device.key] = nil
      sessionErrors[device.key] = error.localizedDescription
      throw error
    }
  }

  private func attachSimulator(_ device: Device) async throws {
    let session = SimulatorSession(deviceKey: device.key, udid: device.rawID)
    session.onStatusChange = { [weak self] status in
      DispatchQueue.main.async { self?.apply(status, key: device.key) }
    }
    sessions[device.key] = session
    do {
      try await session.start()
    } catch {
      sessions[device.key] = nil
      sessionErrors[device.key] = error.localizedDescription
      throw error
    }
  }

  private func apply(_ status: SessionStatus, key: String) {
    if case .failed(let message) = status {
      sessionErrors[key] = message
      sessions[key]?.stop()
      sessions[key] = nil
      fps[key] = nil
    }
    objectWillChange.send()
  }

  private func measureFPS() {
    let now = Date()
    for (key, session) in sessions {
      let count = session.framesShown
      if let sample = fpsSamples[key] {
        let seconds = now.timeIntervalSince(sample.time)
        if seconds >= 0.5 {
          fps[key] = max(0, Double(count - sample.count) / seconds)
          fpsSamples[key] = (count, now)
        }
      } else {
        fpsSamples[key] = (count, now)
      }
    }
    for key in fpsSamples.keys where sessions[key] == nil {
      fpsSamples[key] = nil
      fps[key] = nil
    }
  }
}
