import AppKit
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
  @Published private(set) var webcams: [String] = []
  @Published private(set) var recordingStarts: [String: Date] = [:]
  @Published private(set) var gridRecordingStart: Date?
  @Published private(set) var gridRecordingURL: URL?
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
  @Published var createSheetShown = false
  @Published var sdkSheetShown = false
  @Published var connectSheetShown = false
  @Published var settingsSheetShown = false
  @Published var createPlatform = 0
  @Published private(set) var discoveredServices: [AdbMdnsService] = []
  @Published var logcatDevice: Device?
  @Published private(set) var logcatLines: [String] = []
  /// Recent notices, newest first; the bell keeps them after the panel clears.
  @Published private(set) var notices: [NoticeEntry] = []
  /// Notices currently on screen, newest first; they stack instead of
  /// covering each other.
  @Published private(set) var banners: [NoticeEntry] = []
  @Published private(set) var unreadNotices = 0

  struct NoticeEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
  }

  private let emulator = EmulatorController()
  private let gridRecorder = GridRecorder()
  let settingsStore = DeviceSettingsStore()
  private var loop: Task<Void, Never>?
  private var fpsSamples: [String: (count: Int, time: Date)] = [:]
  private var misses: [String: Int] = [:]
  private var streamRetries: [String: Int] = [:]
  private var streamLiveSince: [String: Date] = [:]
  private var recordings: [String: CaptureService.ActiveRecording] = [:]
  private var mcpServer: McpServer?
  private var logcatProcess: Process?
  private var logcatBuffer = ""
  /// `devicectl` costs a second or two; the device list refreshes every
  /// three, so physical iOS devices are re-read less often.
  private var physicalIOSDevices: [Device] = []
  private var physicalIOSCheckedAt = Date.distantPast

  var runningDevices: [Device] { devices.filter(\.isRunning) }
  var androidDevices: [Device] {
    devices.filter { $0.os == .android && $0.kind == .physical }
  }
  var iosDevices: [Device] {
    devices.filter { $0.os == .ios && $0.kind == .physical }
  }
  var iosSimulators: [Device] {
    devices.filter { $0.os == .ios && $0.kind == .simulator }
  }

  /// The devices whose streams are open, in grid order.
  var openDevices: [Device] {
    openKeys.compactMap { key in devices.first { $0.key == key } }
  }

  var emulatorAvailable: Bool { ShellEnv.exists(ShellEnv.emulatorPath) }
  var adbAvailable: Bool { ShellEnv.exists(ShellEnv.adbPath) }

  // MARK: - Lifecycle

  func start() async {
    androidHome = ShellEnv.androidHome
    CaptureService.folderOverride = settingsStore.recordingDirectory
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
    if let raw = ProcessInfo.processInfo.environment["SIMDECK_LAYOUT"],
      let value = StreamLayout(rawValue: raw)
    {
      settingsStore.setLayout(value)
    }
    webcams = await EmulatorController.listWebcams()
    if ProcessInfo.processInfo.environment["SIMDECK_SHOW_SDK"] == "1" {
      sdkSheetShown = true
    }
    if ProcessInfo.processInfo.environment["SIMDECK_SHOW_CONNECT"] == "1" {
      connectSheetShown = true
    }
    if ProcessInfo.processInfo.environment["SIMDECK_SHOW_SETTINGS"] == "1" {
      settingsSheetShown = true
    }
    if ProcessInfo.processInfo.environment["SIMDECK_SHOW_LOGCAT"] == "1",
      let device = devices.first(where: { $0.os == .android && $0.isRunning })
    {
      openLogcat(device)
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
    let physical = await loadPhysicalIOS()
    devices = await (simulators + android + ios) + physical
    openKeys.removeAll { key in !devices.contains { $0.key == key } }
    pruneSessions()
  }

  private func loadPhysicalIOS() async -> [Device] {
    if Date().timeIntervalSince(physicalIOSCheckedAt) < 15 {
      return physicalIOSDevices
    }
    physicalIOSCheckedAt = Date()
    physicalIOSDevices = await DevicectlService.listPhysicalDevices()
    return physicalIOSDevices
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
        name: avd.displayName,
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

  /// Boots [device]; [stream] opens its tile in the grid. Agents boot with
  /// `stream: false` when they only need adb/simctl, and always headless so
  /// no emulator window appears.
  func start(
    _ device: Device, coldBoot: Bool? = nil, headless: Bool? = nil,
    stream: Bool = true
  ) async {
    guard !busy.contains(device.key) else { return }
    busy.insert(device.key)
    defer { busy.remove(device.key) }
    do {
      switch device.os {
      case .android:
        if device.kind == .simulator {
          if device.isRunning {
            // Already booted (possibly by an earlier call): never start a
            // second emulator for the same AVD.
            if stream, let serial = device.serial {
              try await attachAndroid(device: device, serial: serial)
            }
          } else {
            let name = device.avdName ?? device.rawID
            let settings = settingsStore.settings(for: device)
            try emulator.start(
              name: name,
              headless: headless ?? settingsStore.isHeadless(device),
              coldBoot: coldBoot ?? settings.coldBoot,
              cameraBack: settings.cameraBack,
              cameraFront: settings.cameraFront)
            guard let serial = await emulator.waitForSerial(avdName: name) else {
              throw EmulatorError.bootTimedOut(name)
            }
            if stream {
              try await attachAndroid(device: device, serial: serial)
            }
          }
        } else if let serial = device.serial, stream {
          try await attachAndroid(device: device, serial: serial)
        }
      case .ios:
        if device.kind == .physical {
          if stream { try await attachPhysical(device) }
        } else {
          guard await SimctlService.boot(udid: device.rawID) else {
            throw SimulatorError("Could not boot \(device.name).")
          }
          if stream { try await attachSimulator(device) }
        }
      }
      if stream, !openKeys.contains(device.key) { openKeys.append(device.key) }
      sessionErrors[device.key] = nil
      await refresh()
      showNotice(stream ? "Started \(device.name)" : "Booted \(device.name)")
    } catch {
      sessionErrors[device.key] = error.localizedDescription
      errorMessage = error.localizedDescription
    }
  }

  func restart(_ device: Device) async {
    guard !busy.contains(device.key) else { return }
    await stop(device)
    await start(device)
  }

  /// Stores the camera override and restarts a running emulator, since the
  /// emulator only reads it at boot.
  func setCameraBack(_ device: Device, source: String?) async {
    settingsStore.update(device) { $0.cameraBack = source }
    objectWillChange.send()
    if device.isRunning { await restart(device) }
  }

  func updateAvd(_ avd: AvdInfo, form: AvdEditForm) async {
    do {
      let running = Set(await AdbService.runningAvds().keys)
      if let issue = DeletionGuard.checkAvd(name: avd.name, running: running) {
        throw issue
      }
      try AvdEditor.update(name: avd.name, form: form)
      // The AVD's own camera applies again unless the user overrides it.
      settingsStore.update(key: "android:\(avd.name)") {
        $0.cameraBack = nil
        $0.cameraFront = nil
      }
      showNotice("Saved \(avd.displayName)")
      await refresh()
    } catch {
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
        try await attachAndroid(device: device, serial: serial)
      case .ios:
        if device.kind == .physical {
          try await attachPhysical(device)
        } else {
          guard device.isRunning else {
            throw SimulatorError("Boot the simulator before streaming it.")
          }
          try await attachSimulator(device)
        }
      }
      if !openKeys.contains(device.key) { openKeys.append(device.key) }
      sessionErrors[device.key] = nil
      showNotice("Streaming \(device.name)")
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
    streamRetries[device.key] = nil
    streamLiveSince[device.key] = nil
  }

  func stop(_ device: Device) async {
    guard !busy.contains(device.key) else { return }
    busy.insert(device.key)
    defer { busy.remove(device.key) }
    if logcatDevice?.key == device.key { closeLogcat() }
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
      if device.kind == .simulator {
        _ = await SimctlService.shutdown(udid: device.rawID)
      }
    }
    await refresh()
    // The emulator needs a moment to drop off adb; refresh again so the row
    // does not linger in RUNNING.
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    await refresh()
    showNotice("Stopped \(device.name)")
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
        guard device.kind == .simulator else {
          throw GuardIssue(
            code: "unsupported", message: "A physical device is removed by unplugging it.")
        }
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
        guard device.kind == .simulator else {
          throw GuardIssue(
            code: "unsupported", message: "A physical device cannot be wiped from here.")
        }
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
  func showFrame(_ device: Device) -> Bool { settingsStore.showFrame(device) }

  func toggleFrame(_ device: Device) {
    let current = showFrame(device)
    settingsStore.update(device) { $0.showFrame = !current }
    objectWillChange.send()
  }

  func deviceSettings(_ device: Device) -> DeviceSettings {
    settingsStore.settings(for: device)
  }

  func isHeadless(_ device: Device) -> Bool { settingsStore.isHeadless(device) }

  var headlessDefault: Bool { settingsStore.headlessDefault }
  var frameDefault: Bool { settingsStore.frameDefault }
  var recordingDirectory: URL { CaptureService.directory }

  func setHeadlessDefault(_ value: Bool) {
    settingsStore.setHeadlessDefault(value)
    objectWillChange.send()
  }

  func setFrameDefault(_ value: Bool) {
    settingsStore.setFrameDefault(value)
    objectWillChange.send()
  }

  func setRecordingFolder(_ path: String) {
    settingsStore.setRecordingFolder(path)
    CaptureService.folderOverride = settingsStore.recordingDirectory
    objectWillChange.send()
  }

  var layout: StreamLayout { settingsStore.layout }
  var spotlightKey: String? { settingsStore.spotlightKey }

  func setLayout(_ value: StreamLayout) {
    settingsStore.setLayout(value)
    objectWillChange.send()
  }

  func spotlight(_ device: Device) {
    settingsStore.setSpotlight(device.key)
    objectWillChange.send()
  }

  /// Moves [key] in front of [target] in the grid order.
  func moveStream(_ key: String, before target: String) {
    guard key != target,
      let from = openKeys.firstIndex(of: key),
      let to = openKeys.firstIndex(of: target)
    else { return }
    var keys = openKeys
    keys.remove(at: from)
    let insert = keys.firstIndex(of: target) ?? min(to, keys.count)
    keys.insert(key, at: insert)
    openKeys = keys
    objectWillChange.send()
  }

  func setHeadless(_ device: Device, _ value: Bool) {
    settingsStore.update(device) { $0.headless = value }
    objectWillChange.send()
  }

  func retry(_ device: Device) async {
    closeStream(device)
    await openStream(device)
  }

  // MARK: - Wireless

  func refreshMdns() async {
    discoveredServices = await AdbService.mdnsServices()
  }

  func pairDevice(hostPort: String, code: String) async -> String {
    let result = await AdbService.pair(hostPort: hostPort, code: code)
    if result.ok { await refreshMdns() }
    if !result.combined.isEmpty { return result.combined }
    return result.ok ? "Paired." : "Pairing failed."
  }

  func connectDevice(hostPort: String) async -> String {
    let address = hostPort.contains(":") ? hostPort : "\(hostPort):5555"
    let result = await AdbService.connect(hostPort: address)
    if result.ok { await refresh() }
    if !result.combined.isEmpty { return result.combined }
    return result.ok ? "Connected." : "Connection failed."
  }

  func disconnectDevice(hostPort: String) async -> String {
    let result = await AdbService.disconnect(hostPort: hostPort)
    await refresh()
    return result.combined.isEmpty ? "Disconnected." : result.combined
  }

  // MARK: - Logcat

  func openLogcat(_ device: Device) {
    guard device.os == .android, let serial = device.serial else {
      errorMessage = "Start the Android device before reading its logcat."
      return
    }
    closeLogcat()
    logcatDevice = device
    logcatLines = []
    logcatBuffer = ""
    logcatProcess = ProcessRunner.launch(
      ShellEnv.adbPath,
      ["-s", serial, "logcat", "-v", "time"],
      onOutput: { [weak self] chunk in
        Task { @MainActor in self?.appendLogcat(chunk) }
      })
  }

  func closeLogcat() {
    logcatProcess?.terminate()
    logcatProcess = nil
    logcatDevice = nil
    logcatBuffer = ""
  }

  func clearLogcat() {
    logcatLines = []
    logcatBuffer = ""
  }

  private func appendLogcat(_ chunk: String) {
    logcatBuffer += chunk
    let parts = logcatBuffer.components(separatedBy: "\n")
    logcatBuffer = parts.last ?? ""
    let complete = parts.dropLast()
    guard !complete.isEmpty else { return }
    logcatLines.append(contentsOf: complete)
    if logcatLines.count > 3000 {
      logcatLines.removeFirst(logcatLines.count - 3000)
    }
  }

  // MARK: - Capture

  func takeScreenshot(_ device: Device) async {
    do {
      if device.os == .ios && device.kind == .physical {
        guard let session = sessions[device.key] as? PhysicalDeviceSession,
          let png = session.snapshotPNG()
        else {
          throw PhysicalCaptureError.message(
            "Stream the device first; its screenshot comes from the live frames.")
        }
        let url = CaptureService.directory.appendingPathComponent(
          "\(CaptureService.safeName(device.name))-\(CaptureService.stamp()).png")
        try png.write(to: url, options: .atomic)
        showNotice("Screenshot saved to \(url.lastPathComponent)")
        return
      }
      let url = try await CaptureService.screenshot(device)
      showNotice("Screenshot saved to \(url.lastPathComponent)")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func isRecording(_ device: Device) -> Bool { recordingStarts[device.key] != nil }

  func recordingStart(_ device: Device) -> Date? { recordingStarts[device.key] }

  @discardableResult
  func toggleRecording(_ device: Device) async -> URL? {
    if isGridRecording {
      errorMessage = "Stop the grid recording before recording one device."
      return nil
    }
    if device.os == .ios && device.kind == .physical {
      errorMessage = "Recording a USB iOS device is not supported yet."
      return nil
    }
    if let active = recordings.removeValue(forKey: device.key) {
      recordingStarts[device.key] = nil
      if let url = await CaptureService.stopRecording(device, recording: active) {
        showNotice("Recording saved to \(url.lastPathComponent)")
        return url
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
    return nil
  }

  // MARK: - Grid recording

  var isGridRecording: Bool { gridRecordingStart != nil }
  var gridQuality: GridRecordQuality { settingsStore.gridQuality }

  func setGridQuality(_ value: GridRecordQuality) {
    settingsStore.setGridQuality(value)
    objectWillChange.send()
  }

  /// `nil` goes back to the saved quality. Returns the file when stopping.
  @discardableResult
  func toggleGridRecording(quality: GridRecordQuality? = nil) async -> URL? {
    if gridRecordingStart != nil {
      let url = await gridRecorder.stop()
      gridRecordingStart = nil
      gridRecordingURL = nil
      guard let url else {
        errorMessage = "Could not finish the grid recording."
        return nil
      }
      showNotice("Recording saved to \(url.lastPathComponent)")
      return url
    }
    guard recordings.isEmpty else {
      errorMessage = "Stop the device recordings before recording the grid."
      return nil
    }
    guard let window = mainWindow() else {
      errorMessage = "Show the SimDeck window before recording the grid."
      return nil
    }
    do {
      let url = try await gridRecorder.start(
        quality: quality ?? settingsStore.gridQuality,
        windowNumber: window.windowNumber)
      gridRecordingStart = gridRecorder.startDate ?? Date()
      gridRecordingURL = url
      showNotice("Recording the grid…")
    } catch {
      errorMessage = error.localizedDescription
    }
    return nil
  }

  /// Recordings in the capture folder, newest first.
  func savedRecordings() -> [URL] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: CaptureService.directory, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles])) ?? []
    return files
      .filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
      .sorted { modified($0) > modified($1) }
  }

  private func modified(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate) ?? .distantPast
  }

  /// The main SwiftUI window; sheets, panels and popovers are excluded.
  private func mainWindow() -> NSWindow? {
    NSApp.windows.first {
      $0.isVisible && $0.sheetParent == nil && $0.styleMask.contains(.titled)
        && !($0 is NSPanel)
    }
  }

  func showNotice(_ text: String) {
    let entry = NoticeEntry(text: text, date: Date())
    notices.insert(entry, at: 0)
    if notices.count > 50 { notices.removeLast(notices.count - 50) }
    unreadNotices += 1
    showBanner(text, at: entry.date)
  }

  /// Shows an old notice again without adding a second history entry.
  func replayNotice(_ entry: NoticeEntry) { showBanner(entry.text, at: entry.date) }

  func markNoticesRead() { unreadNotices = 0 }

  func clearNotices() {
    notices = []
    unreadNotices = 0
  }

  func dismissBanner(_ id: UUID) {
    banners.removeAll { $0.id == id }
  }

  /// The on-screen stack keeps the newest five; each one clears itself.
  private func showBanner(_ text: String, at date: Date) {
    let banner = NoticeEntry(text: text, date: date)
    banners.insert(banner, at: 0)
    if banners.count > 5 { banners.removeLast(banners.count - 5) }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 6_000_000_000)
      self?.dismissBanner(banner.id)
    }
  }

  // MARK: - Apps

  func installApp(_ device: Device, path: String) async throws {
    let result: ProcessResult
    switch device.os {
    case .android:
      guard let serial = device.serial else {
        throw GuardIssue(code: "device_stopped", message: "Start \(device.name) first.")
      }
      result = await AdbService.install(serial: serial, path: path)
    case .ios:
      guard device.kind == .simulator else {
        throw GuardIssue(
          code: "unsupported", message: "Installing on a USB iOS device is not supported.")
      }
      result = await SimctlService.install(udid: device.rawID, path: path)
    }
    guard result.ok else {
      throw GuardIssue(
        code: "install_failed",
        message: result.combined.isEmpty ? "Could not install \(path)." : result.combined)
    }
    showNotice("Installed \((path as NSString).lastPathComponent)")
  }

  func launchApp(_ device: Device, app: String, clearState: Bool) async throws {
    let result: ProcessResult
    switch device.os {
    case .android:
      guard let serial = device.serial else {
        throw GuardIssue(code: "device_stopped", message: "Start \(device.name) first.")
      }
      result = await AdbService.launch(serial: serial, app: app, clearState: clearState)
      if result.combined.contains("No activities found") {
        throw GuardIssue(code: "app_not_found", message: "No launchable activity for \(app).")
      }
    case .ios:
      guard device.kind == .simulator else {
        throw GuardIssue(
          code: "unsupported", message: "Launching on a USB iOS device is not supported.")
      }
      guard !clearState else {
        throw GuardIssue(
          code: "unsupported", message: "clear_state is not supported on iOS simulators.")
      }
      result = await SimctlService.launch(udid: device.rawID, app: app)
    }
    guard result.ok else {
      throw GuardIssue(
        code: "launch_failed",
        message: result.combined.isEmpty ? "Could not launch \(app)." : result.combined)
    }
    showNotice("Launched \(app)")
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

  /// Android devices stream through scrcpy. If another adb client kills the
  /// shared server, `apply` schedules an automatic reconnect.
  private func attachAndroid(device: Device, serial: String) async throws {
    try await attachScrcpy(device: device, serial: serial)
  }

  private func attachScrcpy(device: Device, serial: String) async throws {
    let session = ScrcpySession(deviceKey: device.key, serial: serial)
    session.onStatusChange = { [weak self, weak session] status in
      DispatchQueue.main.async {
        guard let self, let session, self.sessions[device.key] === session else { return }
        self.apply(status, key: device.key)
      }
    }
    sessions[device.key] = session
    do {
      try await Task.detached(priority: .userInitiated) {
        try await session.start()
      }.value
    } catch {
      session.stop()
      sessions[device.key] = nil
      sessionErrors[device.key] = error.localizedDescription
      throw error
    }
  }

  private func attachSimulator(_ device: Device) async throws {
    let session = SimulatorSession(deviceKey: device.key, udid: device.rawID)
    session.onStatusChange = { [weak self, weak session] status in
      DispatchQueue.main.async {
        guard let self, let session, self.sessions[device.key] === session else { return }
        self.apply(status, key: device.key)
      }
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

  /// A USB iPhone / iPad; view only, no boot step.
  private func attachPhysical(_ device: Device) async throws {
    let session = PhysicalDeviceSession(
      deviceKey: device.key, udid: device.rawID, name: device.name)
    session.onStatusChange = { [weak self, weak session] status in
      DispatchQueue.main.async {
        guard let self, let session, self.sessions[device.key] === session else { return }
        self.apply(status, key: device.key)
      }
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
      // A stream that dies right after going live is not healthy: only a
      // stretch of real frames earns a fresh set of reconnect attempts.
      if let since = streamLiveSince.removeValue(forKey: key),
        Date().timeIntervalSince(since) >= 30
      {
        streamRetries[key] = 0
      }
      sessionErrors[key] = message
      sessions[key]?.stop()
      sessions[key] = nil
      fps[key] = nil
      scheduleReconnect(key)
    } else if case .live = status {
      streamLiveSince[key] = Date()
    }
    objectWillChange.send()
  }

  /// scrcpy dies with the adb server, which other tools also kill. Reopen the
  /// tile a few times with a backoff while the device itself is still running.
  private func scheduleReconnect(_ key: String) {
    guard openKeys.contains(key),
      let device = devices.first(where: { $0.key == key }), device.isRunning
    else { return }
    let attempt = streamRetries[key, default: 0]
    guard attempt < 3 else { return }
    streamRetries[key] = attempt + 1
    if attempt == 0 { showNotice("Reconnecting \(device.name)…") }
    let delay = [1.0, 2.0, 4.0][min(attempt, 2)]
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard let self, self.openKeys.contains(key), self.sessions[key] == nil else {
        return
      }
      await self.refresh()
      guard self.openKeys.contains(key),
        let device = self.devices.first(where: { $0.key == key }), device.isRunning
      else { return }
      await self.openStream(device)
      if self.sessions[key] == nil { self.scheduleReconnect(key) }
    }
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
