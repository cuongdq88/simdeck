import AVFoundation
import Foundation

/// Plays the PCM (16-bit, 48 kHz, stereo) the scrcpy server captures from an
/// Android device. Audio is best-effort: if the engine cannot start, the tile
/// keeps streaming silently.
final class AudioSink {
  /// Packets waiting to play. Beyond this the newest packet is dropped, so a
  /// slow output device cannot build up seconds of delay.
  private static let maxPending = 8

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let queue = DispatchQueue(label: "dev.simdeck.audio", qos: .userInitiated)
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2,
    interleaved: true)!

  private var pending = 0
  private var started = false
  private var closed = false

  init() {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }

  /// Accepts one raw PCM packet. Never blocks the caller, never throws.
  func append(_ data: Data) {
    queue.async { [weak self] in
      guard let self, !self.closed, data.count >= 4 else { return }
      guard self.pending < Self.maxPending else { return }
      let frames = data.count / 4
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: self.format, frameCapacity: AVAudioFrameCount(frames)),
        let channel = buffer.int16ChannelData?[0]
      else { return }
      buffer.frameLength = AVAudioFrameCount(frames)
      data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        memcpy(channel, base, frames * 4)
      }
      if !self.started {
        do {
          try self.engine.start()
          self.player.play()
          self.started = true
        } catch {
          NSLog("SimDeck audio start failed: %@", error.localizedDescription)
          self.closed = true
          return
        }
      }
      self.pending += 1
      self.player.scheduleBuffer(buffer) { [weak self] in
        guard let self else { return }
        self.queue.async { self.pending = max(0, self.pending - 1) }
      }
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self, !self.closed else { return }
      self.closed = true
      self.player.stop()
      self.engine.stop()
    }
  }
}
