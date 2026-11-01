import CoreMedia
import Foundation
import VideoToolbox

/// Decodes H.264 Annex-B access units with VideoToolbox and hands each frame
/// to `onFrame`. Frames are dropped while the decoder is behind so a slow
/// decoder never grows an unbounded queue.
final class H264Decoder {
  static let maxBacklog = 6

  private let queue = DispatchQueue(label: "dev.simdeck.h264", qos: .userInteractive)
  private let lock = NSLock()
  private var decoded = 0
  private var backlog = 0
  private var waitingForKey = false
  private var armed = false

  private var session: VTDecompressionSession?
  private var format: CMVideoFormatDescription?
  private var sps: Data?
  private var pps: Data?

  /// Called from a decoder thread after each frame.
  var onFrame: ((CVPixelBuffer) -> Void)?

  private(set) var accepted = 0

  deinit {
    invalidate()
  }

  /// Queues one access unit. Returns true when the decoder dropped frames and
  /// needs a key frame to resume.
  func decode(_ data: Data) -> Bool {
    lock.lock()
    let queued = backlog
    let done = decoded
    lock.unlock()
    if done > 0 && (queued < Self.maxBacklog || done > 60) { armed = true }
    let busy = armed && queued >= Self.maxBacklog
    if waitingForKey || busy {
      if Self.isKeyFrame(data) {
        waitingForKey = false
      } else {
        waitingForKey = true
        return true
      }
    }
    lock.lock()
    backlog += 1
    lock.unlock()
    accepted += 1
    queue.async { [self] in
      if !decodeNow(data) { finished() }
    }
    return false
  }

  func stop() {
    queue.sync {
      invalidate()
      onFrame = nil
    }
  }

  private func finished() {
    lock.lock()
    backlog -= 1
    lock.unlock()
  }

  private func decodeNow(_ data: Data) -> Bool {
    let nals = Self.nalRanges(data)
    var sliceBytes = 0
    for range in nals {
      switch data[range.lowerBound] & 0x1f {
      case 7:
        if sps.map({ !$0.elementsEqual(data[range]) }) ?? true {
          sps = Data(data[range])
          invalidate()
        }
      case 8:
        if pps.map({ !$0.elementsEqual(data[range]) }) ?? true {
          pps = Data(data[range])
          invalidate()
        }
      case 9:
        break
      default:
        sliceBytes += 4 + range.count
      }
    }
    if session == nil { createSession() }
    guard let session, let format, sliceBytes > 0,
      let sample = Self.sample(data, nals: nals, size: sliceBytes, format: format)
    else { return false }

    let status = VTDecompressionSessionDecodeFrame(
      session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
    ) { [weak self] status, _, image, _, _ in
      guard let self else { return }
      if status == noErr, let image {
        self.lock.lock()
        self.decoded += 1
        self.lock.unlock()
        self.onFrame?(image)
      }
      self.finished()
    }
    if status != noErr {
      if status == kVTInvalidSessionErr { invalidate() }
      return false
    }
    return true
  }

  private func createSession() {
    guard let sps, let pps else { return }
    var format: CMVideoFormatDescription?
    let status = sps.withUnsafeBytes { spsBytes in
      pps.withUnsafeBytes { ppsBytes in
        let sets = [
          spsBytes.bindMemory(to: UInt8.self).baseAddress!,
          ppsBytes.bindMemory(to: UInt8.self).baseAddress!,
        ]
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: nil, parameterSetCount: 2, parameterSetPointers: sets,
          parameterSetSizes: [sps.count, pps.count], nalUnitHeaderLength: 4,
          formatDescriptionOut: &format)
      }
    }
    guard status == noErr, let format else { return }
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    var session: VTDecompressionSession?
    guard
      VTDecompressionSessionCreate(
        allocator: nil, formatDescription: format, decoderSpecification: nil,
        imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
        decompressionSessionOut: &session) == noErr, let session
    else { return }
    VTSessionSetProperty(
      session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    self.format = format
    self.session = session
  }

  private func invalidate() {
    if let session {
      VTDecompressionSessionWaitForAsynchronousFrames(session)
      VTDecompressionSessionInvalidate(session)
    }
    session = nil
    format = nil
  }

  /// True when [data] starts at an IDR slice or SPS.
  static func isKeyFrame(_ data: Data) -> Bool {
    for range in nalRanges(data) {
      switch data[range.lowerBound] & 0x1f {
      case 5, 7: return true
      case 1: return false
      default: continue
      }
    }
    return false
  }

  /// NAL payload ranges between Annex-B start codes.
  static func nalRanges(_ data: Data) -> [Range<Int>] {
    data.withUnsafeBytes { raw -> [Range<Int>] in
      let bytes = raw.bindMemory(to: UInt8.self)
      let base = data.startIndex
      var starts: [(code: Int, payload: Int)] = []
      var i = 0
      while i + 2 < bytes.count {
        if bytes[i + 2] > 1 {
          i += 3
        } else if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
          starts.append((i > 0 && bytes[i - 1] == 0 ? i - 1 : i, i + 3))
          i += 3
        } else {
          i += 1
        }
      }
      return starts.indices.compactMap { k in
        let end = k + 1 < starts.count ? starts[k + 1].code : bytes.count
        return starts[k].payload < end ? (base + starts[k].payload)..<(base + end) : nil
      }
    }
  }

  private static func sample(
    _ data: Data, nals: [Range<Int>], size: Int, format: CMVideoFormatDescription
  ) -> CMSampleBuffer? {
    var block: CMBlockBuffer?
    guard
      CMBlockBufferCreateWithMemoryBlock(
        allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil,
        customBlockSource: nil, offsetToData: 0, dataLength: size,
        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
      let block
    else { return nil }
    var out: UnsafeMutablePointer<CChar>?
    guard
      CMBlockBufferGetDataPointer(
        block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil,
        dataPointerOut: &out) == noErr, let out
    else { return nil }
    var offset = 0
    data.withUnsafeBytes { raw in
      for range in nals {
        switch data[range.lowerBound] & 0x1f {
        case 7, 8, 9: continue
        default: break
        }
        var length = UInt32(range.count).bigEndian
        memcpy(out + offset, &length, 4)
        memcpy(
          out + offset + 4, raw.baseAddress! + (range.lowerBound - data.startIndex),
          range.count)
        offset += 4 + range.count
      }
    }
    var sample: CMSampleBuffer?
    var sampleSize = size
    guard
      CMSampleBufferCreateReady(
        allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr
    else { return nil }
    return sample
  }
}
