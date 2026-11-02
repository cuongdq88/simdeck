import AVFoundation
import CoreImage
import CoreMedia
import CoreMediaIO

enum PhysicalCaptureError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}

/// Shows iOS devices on USB as `.muxed` capture devices. Set once per
/// process, before discovery; devices appear a moment later.
private let allowScreenCaptureDevices: Void = {
  var property = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(
      kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
  var allow: UInt32 = 1
  CMIOObjectSetPropertyData(
    CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil,
    UInt32(MemoryLayout<UInt32>.size), &allow)
}()

/// Captures one USB iPhone / iPad screen with CoreMediaIO, the same source
/// QuickTime records from.
final class PhysicalDeviceCapture: NSObject,
  AVCaptureVideoDataOutputSampleBufferDelegate
{
  private let session = AVCaptureSession()
  private let queue = DispatchQueue(
    label: "dev.simdeck.device-capture", qos: .userInteractive)
  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  private var observers: [NSObjectProtocol] = []
  private var connected: NSKeyValueObservation?

  var onFrame: ((CVPixelBuffer) -> Void)?
  var onSize: ((CGSize) -> Void)?
  /// Called on the main thread when the device is unplugged or the capture
  /// dies.
  var onEnded: (() -> Void)?

  init(device: AVCaptureDevice) throws {
    super.init()
    session.addInput(try AVCaptureDeviceInput(device: device))
    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(output) else {
      throw PhysicalCaptureError.message("Could not capture \(device.localizedName)")
    }
    session.addOutput(output)

    let center = NotificationCenter.default
    let identifier = device.uniqueID
    observers = [
      // The posted object may not be ours, so match by identifier.
      center.addObserver(
        forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main
      ) { [weak self] notification in
        if (notification.object as? AVCaptureDevice)?.uniqueID == identifier {
          self?.onEnded?()
        }
      },
      center.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification, object: session,
        queue: .main
      ) { [weak self] _ in self?.onEnded?() },
    ]
    connected = device.observe(\.isConnected) { [weak self] device, _ in
      guard !device.isConnected else { return }
      DispatchQueue.main.async { self?.onEnded?() }
    }
  }

  func start() {
    queue.async { self.session.startRunning() }
  }

  func stop() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    connected = nil
    onEnded = nil
    queue.sync {
      session.stopRunning()
      onFrame = nil
      onSize = nil
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // Capture buffers are not recycled while retained, so no copy is needed.
    guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let size = CGSize(
      width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))
    lock.lock()
    let changed = latest.map {
      CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0))
        != size
    } ?? true
    latest = frame
    lock.unlock()
    if changed { onSize?(size) }
    onFrame?(frame)
  }

  /// The latest frame as PNG.
  func png() -> Data? {
    lock.lock()
    let frame = latest
    lock.unlock()
    guard let frame else { return nil }
    return CIContext().pngRepresentation(
      of: CIImage(cvPixelBuffer: frame), format: .RGBA8,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
  }

  /// The capture device for [name]. Its uniqueID is not the device's UDID,
  /// so it is matched by name; never fall back to the only capture device,
  /// which may be another iPhone.
  @MainActor
  static func find(name: String) async throws -> AVCaptureDevice {
    _ = allowScreenCaptureDevices
    let deadline = Date().addingTimeInterval(6)
    while true {
      let devices = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external], mediaType: .muxed, position: .unspecified
      ).devices
      if let match = devices.first(where: { $0.localizedName == name }) {
        return match
      }
      if Date() > deadline {
        throw PhysicalCaptureError.message(
          "\(name) is not connected by USB cable (or is locked). Streaming over "
            + "Wi-Fi is not supported: connect it with a cable and unlock it.")
      }
      try? await Task.sleep(nanoseconds: 250_000_000)
    }
  }
}

/// Streams a USB iPhone / iPad screen. View only: real devices take no input
/// without an XCUITest runner.
final class PhysicalDeviceSession: DeviceSession {
  let deviceKey: String
  let udid: String
  let name: String
  let sink = VideoSink()
  var onStatusChange: ((SessionStatus) -> Void)?

  private let lock = NSLock()
  private var _status: SessionStatus = .connecting
  private var _size: CGSize = .zero
  private var capture: PhysicalDeviceCapture?

  init(deviceKey: String, udid: String, name: String) {
    self.deviceKey = deviceKey
    self.udid = udid
    self.name = name
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
    guard await AVCaptureDevice.requestAccess(for: .video) else {
      throw PhysicalCaptureError.message(
        "SimDeck needs Camera access to show a USB device's screen: allow it in "
          + "System Settings › Privacy & Security › Camera.")
    }
    let device = try await PhysicalDeviceCapture.find(name: name)
    let capture = try PhysicalDeviceCapture(device: device)
    capture.onFrame = { [weak self] frame in self?.sink.enqueue(frame) }
    capture.onSize = { [weak self] size in self?.setSize(size) }
    capture.onEnded = { [weak self] in
      self?.emit(.failed("The device was disconnected."))
    }
    lock.lock()
    self.capture = capture
    lock.unlock()
    capture.start()
    emit(.live)
  }

  func stop() {
    lock.lock()
    let capture = self.capture
    self.capture = nil
    lock.unlock()
    capture?.stop()
    sink.reset()
  }

  /// The latest frame as PNG, for screenshots.
  func snapshotPNG() -> Data? { capture?.png() }

  private func setSize(_ size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    lock.lock()
    _size = size
    lock.unlock()
  }

  private func emit(_ next: SessionStatus) {
    lock.lock()
    _status = next
    let handler = onStatusChange
    lock.unlock()
    handler?(next)
  }

  // View only: a real device takes no input without an XCUITest runner.
  func touch(_ phase: TouchPhase, x: Double, y: Double) {}
  func press(_ button: DeviceButton) {}
  func typeText(_ text: String) {}
  func rotate() {}
}
