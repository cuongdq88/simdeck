import Cocoa
import CoreVideo
import IOSurface

/// Captures one simulator's framebuffer and hands each frame over as a
/// pixel buffer the display layer can hold.
final class SimulatorCapture {
  private let queue = DispatchQueue(label: "dev.simdeck.sim-capture", qos: .userInteractive)
  private var pool: CVPixelBufferPool?
  private var poolSize = (0, 0)
  private var descriptors: [(NSObject, UUID)] = []
  private var lastSeed: UInt32?
  private var expectedSize: CGSize?
  private var io: NSObject?
  private var rewireTimer: DispatchSourceTimer?
  private var frames = 0

  private let onFrame: (CVPixelBuffer) -> Void
  private let onSize: (CGSize) -> Void

  init(onFrame: @escaping (CVPixelBuffer) -> Void, onSize: @escaping (CGSize) -> Void) {
    self.onFrame = onFrame
    self.onSize = onSize
  }

  func start(device: NSObject) throws {
    expectedSize = SimFrameworks.mainScreenSize(device)
    guard let io = device.perform(NSSelectorFromString("io"))?.takeUnretainedValue() as? NSObject
    else { throw SimulatorError("Simulator IO is unavailable") }
    self.io = io
    try queue.sync { try wire() }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in
      guard let self, self.frames == 0 else { return }
      try? self.wire()
    }
    timer.resume()
    rewireTimer = timer
  }

  func stop() {
    rewireTimer?.cancel()
    rewireTimer = nil
    queue.sync { unregister() }
    io = nil
  }

  private func wire() throws {
    guard let io else { return }
    io.perform(NSSelectorFromString("updateIOPorts"))
    unregister()
    guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else {
      throw SimulatorError("Simulator has no IO ports")
    }
    let surfaceSelector = NSSelectorFromString("framebufferSurface")
    for port in ports {
      guard
        let identifier = port.perform(NSSelectorFromString("portIdentifier"))?
          .takeUnretainedValue(),
        "\(identifier)" == "com.apple.framebuffer.display",
        let descriptor = port.perform(NSSelectorFromString("descriptor"))?
          .takeUnretainedValue() as? NSObject,
        descriptor.responds(to: surfaceSelector),
        descriptor.responds(to: #selector(FramebufferDescriptor.registerScreenCallbacks))
      else { continue }
      let uuid = UUID()
      unsafeBitCast(descriptor, to: FramebufferDescriptor.self).registerScreenCallbacks(
        uuid: uuid, callbackQueue: queue,
        frameCallback: { [weak self] in self?.capture() },
        surfacesChangedCallback: { [weak self] in self?.capture() },
        propertiesChangedCallback: {})
      descriptors.append((descriptor, uuid))
    }
    if descriptors.isEmpty {
      throw SimulatorError("No simulator display found (is the device booted?)")
    }
    capture()
  }

  private func unregister() {
    let selector = NSSelectorFromString("unregisterScreenCallbacksWithUUID:")
    for (descriptor, uuid) in descriptors where descriptor.responds(to: selector) {
      descriptor.perform(selector, with: uuid)
    }
    descriptors.removeAll()
  }

  /// Xcode 27 Device Hub may publish a large presentation surface besides the
  /// device display, so match the native size before taking the largest.
  private func currentSurface() -> IOSurface? {
    let selector = NSSelectorFromString("framebufferSurface")
    let surfaces: [IOSurface] = descriptors.compactMap { descriptor, _ in
      guard let object = descriptor.perform(selector)?.takeUnretainedValue() else { return nil }
      return unsafeBitCast(object, to: IOSurface.self)
    }.filter { IOSurfaceGetWidth($0) > 0 && IOSurfaceGetHeight($0) > 0 }

    if let expected = expectedSize {
      let w = Int(expected.width.rounded())
      let h = Int(expected.height.rounded())
      if let match = surfaces.first(where: {
        let sw = IOSurfaceGetWidth($0)
        let sh = IOSurfaceGetHeight($0)
        return (sw == w && sh == h) || (sw == h && sh == w)
      }) {
        return match
      }
    }
    return surfaces.max {
      IOSurfaceGetWidth($0) * IOSurfaceGetHeight($0)
        < IOSurfaceGetWidth($1) * IOSurfaceGetHeight($1)
    }
  }

  private func capture() {
    guard let surface = currentSurface() else { return }
    let seed = IOSurfaceGetSeed(surface)
    if seed == lastSeed { return }
    lastSeed = seed

    var wrapped: Unmanaged<CVPixelBuffer>?
    guard
      CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &wrapped)
        == kCVReturnSuccess,
      let source = wrapped?.takeRetainedValue(),
      let copy = copyBuffer(source)
    else { return }

    frames += 1
    let size = CGSize(
      width: CVPixelBufferGetWidth(copy), height: CVPixelBufferGetHeight(copy))
    onSize(size)
    onFrame(copy)
  }

  /// The simulator recycles its IOSurface, so copy into a pooled buffer the
  /// display layer can keep.
  private func copyBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(source)
    let height = CVPixelBufferGetHeight(source)
    if pool == nil || poolSize != (width, height) {
      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        kCVPixelBufferMetalCompatibilityKey as String: true,
      ]
      CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
      poolSize = (width, height)
    }
    var output: CVPixelBuffer?
    guard let pool,
      CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess,
      let destination = output
    else { return nil }

    CVPixelBufferLockBaseAddress(source, .readOnly)
    CVPixelBufferLockBaseAddress(destination, [])
    defer {
      CVPixelBufferUnlockBaseAddress(destination, [])
      CVPixelBufferUnlockBaseAddress(source, .readOnly)
    }
    guard
      let sourceAddress = CVPixelBufferGetBaseAddress(source),
      let destinationAddress = CVPixelBufferGetBaseAddress(destination)
    else { return nil }

    let sourceStride = CVPixelBufferGetBytesPerRow(source)
    let destinationStride = CVPixelBufferGetBytesPerRow(destination)
    if sourceStride == destinationStride {
      memcpy(destinationAddress, sourceAddress, sourceStride * height)
    } else {
      let rowBytes = min(sourceStride, destinationStride)
      for row in 0..<height {
        memcpy(
          destinationAddress + row * destinationStride,
          sourceAddress + row * sourceStride, rowBytes)
      }
    }
    return destination
  }
}
