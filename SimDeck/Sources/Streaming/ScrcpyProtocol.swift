import Foundation

/// Byte layouts of the scrcpy 4.x server protocol.
enum Scrcpy {
  static let codecH264: UInt32 = 0x6832_3634

  static let flagSession: UInt32 = 0x8000_0000
  static let flagConfig: UInt64 = 1 << 62
  static let flagKeyFrame: UInt64 = 1 << 61
  static let ptsMask: UInt64 = (1 << 61) - 1

  static let msgInjectKeycode: UInt8 = 0
  static let msgInjectText: UInt8 = 1
  static let msgInjectTouch: UInt8 = 2
  static let msgSetDisplayPower: UInt8 = 10
  static let msgRotateDevice: UInt8 = 11
  static let msgResetVideo: UInt8 = 17

  static let keyHome: Int32 = 3
  static let keyBack: Int32 = 4
  static let keyAppSwitch: Int32 = 187
  static let keyPower: Int32 = 26
  static let keyVolumeUp: Int32 = 24
  static let keyVolumeDown: Int32 = 25

  static let fingerPointerID: UInt64 = 0
  static let maxTextBytes = 300
}

struct ScrcpyPacket {
  let data: Data
  let isConfig: Bool
  let isKeyFrame: Bool
  let ptsMicros: Int64
}

enum ScrcpyVideoItem {
  case session(width: Int, height: Int)
  case packet(ScrcpyPacket)
}

/// Incremental parser for the video socket after its dummy byte: the codec
/// id, then 12-byte session headers and 12-byte framed media packets.
struct ScrcpyVideoParser {
  private var buffer = Data()
  private(set) var codec: UInt32?

  mutating func add(_ chunk: Data) -> [ScrcpyVideoItem] {
    buffer.append(chunk)
    var items: [ScrcpyVideoItem] = []
    var offset = 0

    if codec == nil {
      guard buffer.count >= 4 else { return items }
      codec = buffer.u32(at: 0)
      offset = 4
    }

    while buffer.count - offset >= 12 {
      let first = buffer.u32(at: offset)
      if first & Scrcpy.flagSession != 0 {
        items.append(
          .session(
            width: Int(buffer.u32(at: offset + 4)),
            height: Int(buffer.u32(at: offset + 8))))
        offset += 12
        continue
      }
      let size = Int(buffer.u32(at: offset + 8))
      guard buffer.count - offset - 12 >= size else { break }
      let payload = buffer.subdata(in: (offset + 12)..<(offset + 12 + size))
      let flags = buffer.u64(at: offset)
      items.append(
        .packet(
          ScrcpyPacket(
            data: payload,
            isConfig: flags & Scrcpy.flagConfig != 0,
            isKeyFrame: flags & Scrcpy.flagKeyFrame != 0,
            ptsMicros: Int64(flags & Scrcpy.ptsMask))))
      offset += 12 + size
    }

    if offset > 0 { buffer.removeSubrange(0..<offset) }
    return items
  }
}

/// Incremental parser for the audio socket after its 4-byte codec id: the
/// same 12-byte packet header as video, then raw PCM samples.
struct ScrcpyAudioParser {
  private var buffer = Data()

  mutating func add(_ chunk: Data) -> [Data] {
    buffer.append(chunk)
    var packets: [Data] = []
    var offset = 0
    while buffer.count - offset >= 12 {
      let size = Int(buffer.u32(at: offset + 8))
      guard size <= 1 << 20 else {
        buffer.removeAll()
        return packets
      }
      guard buffer.count - offset - 12 >= size else { break }
      packets.append(buffer.subdata(in: (offset + 12)..<(offset + 12 + size)))
      offset += 12 + size
    }
    if offset > 0 { buffer.removeSubrange(0..<offset) }
    return packets
  }
}

enum ScrcpyControl {
  /// `INJECT_KEYCODE` (14 bytes); [action] 0 down, 1 up.
  static func keycode(action: UInt8, code: Int32, metaState: Int32 = 0) -> Data {
    var writer = ByteWriter()
    writer.u8(Scrcpy.msgInjectKeycode)
    writer.u8(action)
    writer.i32be(code)
    writer.i32be(0)
    writer.i32be(metaState)
    return writer.data
  }

  /// `INJECT_TEXT`: type, u32 byte count, UTF-8 text (cut at 300 bytes).
  static func text(_ value: String) -> Data {
    var bytes = Data(value.utf8)
    if bytes.count > Scrcpy.maxTextBytes { bytes = bytes.prefix(Scrcpy.maxTextBytes) }
    var writer = ByteWriter()
    writer.u8(Scrcpy.msgInjectText)
    writer.u32be(UInt32(bytes.count))
    writer.bytes(bytes)
    return writer.data
  }

  /// `INJECT_TOUCH_EVENT` (32 bytes); coordinates are pixels of the video.
  static func touch(
    action: UInt8, x: Int32, y: Int32, width: UInt16, height: UInt16
  ) -> Data {
    var writer = ByteWriter()
    writer.u8(Scrcpy.msgInjectTouch)
    writer.u8(action)
    writer.u64be(Scrcpy.fingerPointerID)
    writer.i32be(x)
    writer.i32be(y)
    writer.u16be(width)
    writer.u16be(height)
    writer.u16be(action == 1 ? 0 : 0xffff)
    writer.i32be(0)
    writer.i32be(0)
    return writer.data
  }

  static func resetVideo() -> Data { Data([Scrcpy.msgResetVideo]) }
  static func rotateDevice() -> Data { Data([Scrcpy.msgRotateDevice]) }
  static func displayPower(_ on: Bool) -> Data {
    Data([Scrcpy.msgSetDisplayPower, on ? 1 : 0])
  }
}

struct ByteWriter {
  private(set) var data = Data()

  mutating func u8(_ value: UInt8) { data.append(value) }

  mutating func u16be(_ value: UInt16) {
    data.append(UInt8(value >> 8))
    data.append(UInt8(value & 0xff))
  }

  mutating func u32be(_ value: UInt32) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
  }

  mutating func u64be(_ value: UInt64) {
    for shift in stride(from: 56, through: 0, by: -8) {
      data.append(UInt8((value >> UInt64(shift)) & 0xff))
    }
  }

  mutating func i32be(_ value: Int32) { u32be(UInt32(bitPattern: value)) }

  mutating func bytes(_ value: Data) { data.append(value) }
}

extension Data {
  func u32(at offset: Int) -> UInt32 {
    let start = startIndex + offset
    guard start + 4 <= endIndex else { return 0 }
    var value: UInt32 = 0
    for index in start..<(start + 4) { value = (value << 8) | UInt32(self[index]) }
    return value
  }

  func u64(at offset: Int) -> UInt64 {
    let start = startIndex + offset
    guard start + 8 <= endIndex else { return 0 }
    var value: UInt64 = 0
    for index in start..<(start + 8) { value = (value << 8) | UInt64(self[index]) }
    return value
  }
}
