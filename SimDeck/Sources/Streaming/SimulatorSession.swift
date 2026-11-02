import CoreGraphics
import Foundation

/// Streams one booted iOS simulator and sends it input.
final class SimulatorSession: DeviceSession {
  let deviceKey: String
  let udid: String
  let sink = VideoSink()
  var onStatusChange: ((SessionStatus) -> Void)?

  private let lock = NSLock()
  private var _status: SessionStatus = .connecting
  private var _size: CGSize = .zero
  private var capture: SimulatorCapture?
  private var hid: SimulatorHID?

  /// Apple's own device frame, when Xcode ships one for this model.
  private(set) var chrome: AppleChrome?

  init(deviceKey: String, udid: String) {
    self.deviceKey = deviceKey
    self.udid = udid
  }

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

  func start() async throws {
    emit(.connecting)
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else {
          continuation.resume(throwing: SimulatorError("The session went away"))
          return
        }
        do {
          try self.startSync()
          continuation.resume()
        } catch {
          self.emit(.failed(error.localizedDescription))
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func startSync() throws {
    guard let device = SimFrameworks.device(udid: udid) else {
      throw SimulatorError("Simulator \(udid) was not found")
    }
    guard (device.value(forKey: "stateString") as? String) == "Booted" else {
      throw SimulatorError("The simulator is not booted")
    }

    let capture = SimulatorCapture(
      onFrame: { [weak self] buffer in self?.sink.enqueue(buffer) },
      onSize: { [weak self] size in self?.setSize(size) })
    try capture.start(device: device)
    lock.lock()
    self.capture = capture
    lock.unlock()

    let hid = try? SimulatorHID(device: device, udid: udid)
    lock.lock()
    self.hid = hid
    lock.unlock()

    let chrome = SimChromeLoader.load(device: device)
    lock.lock()
    self.chrome = chrome
    lock.unlock()

    if let native = SimFrameworks.mainScreenSize(device) {
      setSize(native)
      hid?.setSize(
        width: Int(native.width.rounded()), height: Int(native.height.rounded()))
    }
    emit(.live)
  }

  func stop() {
    lock.lock()
    let capture = self.capture
    self.capture = nil
    self.hid = nil
    lock.unlock()
    capture?.stop()
    sink.reset()
  }

  private func setSize(_ size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    lock.lock()
    let changed = _size != size
    _size = size
    let hid = self.hid
    lock.unlock()
    if changed {
      hid?.setSize(width: Int(size.width), height: Int(size.height))
    }
  }

  func touch(_ phase: TouchPhase, x: Double, y: Double) {
    lock.lock()
    let hid = self.hid
    lock.unlock()
    let name: String
    switch phase {
    case .down: name = "down"
    case .move: name = "move"
    case .up: name = "up"
    }
    hid?.touch(
      phase: name, x: min(max(x, 0), 1), y: min(max(y, 0), 1))
  }

  func press(_ button: DeviceButton) {
    lock.lock()
    let hid = self.hid
    lock.unlock()
    hid?.press(button.rawValue)
  }

  func typeText(_ text: String) {
    lock.lock()
    let hid = self.hid
    lock.unlock()
    hid?.type(text)
  }

  func rotate() {
    lock.lock()
    let hid = self.hid
    lock.unlock()
    guard let hid else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      _ = hid.rotate()
    }
  }

  private func emit(_ next: SessionStatus) {
    lock.lock()
    _status = next
    let handler = onStatusChange
    lock.unlock()
    handler?(next)
  }
}
