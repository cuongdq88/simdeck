import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum GridRecordQuality: String, CaseIterable, Identifiable {
  case low
  case standard
  case high
  case smooth

  var id: String { rawValue }

  var fps: Int {
    switch self {
    case .low: return 15
    case .standard: return 24
    case .high: return 30
    case .smooth: return 60
    }
  }

  /// Long-edge cap; nil keeps the window's own resolution.
  var maxWidth: Int? {
    switch self {
    case .low: return 720
    case .standard: return 1280
    case .high, .smooth: return nil
    }
  }

  var label: String {
    switch self {
    case .low: return "Low — 15 fps, 720p"
    case .standard: return "Standard — 24 fps, 1280 px"
    case .high: return "High — 30 fps, full size"
    case .smooth: return "Smooth — 60 fps, full size"
    }
  }

  var bitrate: Int {
    switch self {
    case .low: return 4_000_000
    case .standard: return 8_000_000
    case .high: return 12_000_000
    case .smooth: return 16_000_000
    }
  }
}

enum GridRecordError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}

/// Records the SimDeck window as a whole with ScreenCaptureKit, so the grid,
/// the spotlight strip and every tile land in one file.
final class GridRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "dev.simdeck.grid-record", qos: .userInitiated)
  private var stream: SCStream?
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var url: URL?
  private var started: Date?

  var isRecording: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started != nil
  }

  var startDate: Date? {
    lock.lock()
    defer { lock.unlock() }
    return started
  }

  /// Frames only land after `startCapture`, so the metadata is stored first.
  func start(quality: GridRecordQuality, windowNumber: Int) async throws -> URL {
    guard !isRecording else {
      throw GridRecordError.message("The grid is already being recorded.")
    }
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    } catch {
      throw GridRecordError.message(
        "Screen Recording permission is needed (System Settings › Privacy & Security › "
          + "Screen Recording), then try again. \(error.localizedDescription)")
    }
    guard
      let window = content.windows.first(where: {
        $0.windowID == CGWindowID(windowNumber)
      })
    else {
      throw GridRecordError.message("The SimDeck window is not shareable yet.")
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let rect = filter.contentRect
    let scale = Double(filter.pointPixelScale)
    var width = Int(Double(rect.width) * scale)
    var height = Int(Double(rect.height) * scale)
    if let cap = quality.maxWidth, width > cap {
      let ratio = Double(cap) / Double(width)
      height = Int(Double(height) * ratio)
      width = cap
    }
    // H.264 needs even dimensions.
    width -= width % 2
    height -= height % 2
    guard width > 1, height > 1 else {
      throw GridRecordError.message("The window has no drawable size yet.")
    }

    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(quality.fps))
    config.queueDepth = 5
    config.showsCursor = false
    config.capturesAudio = false
    config.pixelFormat = kCVPixelFormatType_32BGRA

    let url = CaptureService.directory.appendingPathComponent(
      "grid-\(CaptureService.stamp()).mp4")
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    } catch {
      throw GridRecordError.message("Could not write \(url.lastPathComponent): \(error.localizedDescription)")
    }
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: quality.bitrate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: quality.fps * 2,
      ],
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
      throw GridRecordError.message("The video writer rejected the frame size.")
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw GridRecordError.message(
        writer.error?.localizedDescription ?? "Could not start writing the video.")
    }
    writer.startSession(atSourceTime: .zero)

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

    lock.lock()
    self.stream = stream
    self.writer = writer
    self.input = input
    self.url = url
    self.started = Date()
    lock.unlock()

    do {
      try await stream.startCapture()
    } catch {
      _ = await stop()
      throw GridRecordError.message("Could not start capturing: \(error.localizedDescription)")
    }
    return url
  }

  /// Stops the stream, finishes the file and returns it when it is playable.
  func stop() async -> URL? {
    lock.lock()
    guard
      let stream, let writer, let input, let url, started != nil
    else {
      lock.unlock()
      return nil
    }
    self.stream = nil
    self.writer = nil
    self.input = nil
    self.url = nil
    self.started = nil
    lock.unlock()

    try? await stream.stopCapture()
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { return nil }
    return url
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer)
    else { return }
    // Skip frames ScreenCaptureKit marks idle or blank.
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let status = attachments.first?[.status] as? NSNumber,
      status.intValue == SCFrameStatus.complete.rawValue
    else { return }

    lock.lock()
    let input = self.input
    let writing = writer?.status == .writing
    lock.unlock()
    guard writing, let input, input.isReadyForMoreMediaData else { return }
    input.append(sampleBuffer)
  }
}
