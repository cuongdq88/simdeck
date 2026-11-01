import AVFoundation
import CoreMedia
import CoreVideo

/// Presents CVPixelBuffers in an `AVSampleBufferDisplayLayer` and counts what
/// it actually accepted, which is what the FPS badge reports.
final class VideoSink {
  let layer = AVSampleBufferDisplayLayer()

  private let queue = DispatchQueue(label: "dev.simdeck.video", qos: .userInteractive)
  private let lock = NSLock()
  private var shown = 0

  init() {
    layer.videoGravity = .resizeAspect
    layer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    layer.isOpaque = true
  }

  var framesShown: Int {
    lock.lock()
    defer { lock.unlock() }
    return shown
  }

  func reset() {
    lock.lock()
    shown = 0
    lock.unlock()
    queue.async { [layer] in layer.flush() }
  }

  func enqueue(_ pixelBuffer: CVPixelBuffer) {
    queue.async { [weak self] in
      guard let self else { return }
      if self.layer.status == .failed { self.layer.flush() }

      var format: CMVideoFormatDescription?
      guard
        CMVideoFormatDescriptionCreateForImageBuffer(
          allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
          formatDescriptionOut: &format) == noErr,
        let format
      else { return }

      var timing = CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
        decodeTimeStamp: .invalid)
      var sample: CMSampleBuffer?
      guard
        CMSampleBufferCreateReadyWithImageBuffer(
          allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
          formatDescription: format, sampleTiming: &timing,
          sampleBufferOut: &sample) == noErr,
        let sample
      else { return }

      if let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sample, createIfNecessary: true)
      {
        if CFArrayGetCount(attachments) > 0 {
          let raw = CFArrayGetValueAtIndex(attachments, 0)
          let dict = unsafeBitCast(raw, to: CFMutableDictionary.self)
          CFDictionarySetValue(
            dict,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
      }

      self.layer.enqueue(sample)
      self.lock.lock()
      self.shown += 1
      self.lock.unlock()
    }
  }
}
