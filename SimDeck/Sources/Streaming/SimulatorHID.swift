import Cocoa

/// Touch, hardware buttons, typing and rotation through SimulatorKit's
/// legacy HID client.
final class SimulatorHID {
  private typealias MouseFunc = @convention(c) (
    UnsafePointer<CGPoint>, UnsafePointer<CGPoint>?, UInt32, Int32, CGFloat, CGFloat, UInt32
  ) -> UnsafeMutableRawPointer?
  private typealias ButtonFunc = @convention(c) (Int32, Int32, Int32) -> UnsafeMutableRawPointer?
  private typealias HIDArbitraryFunc = @convention(c) (
    UInt32, UInt32, UInt32, UInt32
  ) -> UnsafeMutableRawPointer?
  private typealias KeyFunc = @convention(c) (UInt32, UInt32) -> UnsafeMutableRawPointer?
  private typealias SendFunc = @convention(c) (
    AnyObject, Selector, UnsafeMutableRawPointer, ObjCBool, AnyObject?, AnyObject?
  ) -> Void

  private let queue = DispatchQueue(label: "dev.simdeck.sim-hid", qos: .userInteractive)
  private let client: NSObject
  private let device: NSObject
  private let mouse: MouseFunc
  private let button: ButtonFunc?
  private let hidArbitrary: HIDArbitraryFunc?
  private let key: KeyFunc?
  private let udid: String
  /// Current `UIDeviceOrientation` for the next rotate.
  private var orientation: UInt32 = 1

  init(device: NSObject, udid: String) throws {
    let handle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
    guard let mousePointer = dlsym(handle, "IndigoHIDMessageForMouseNSEvent") else {
      throw SimulatorError("Simulator touch input is unavailable")
    }
    mouse = unsafeBitCast(mousePointer, to: MouseFunc.self)
    button = dlsym(handle, "IndigoHIDMessageForButton").map {
      unsafeBitCast($0, to: ButtonFunc.self)
    }
    hidArbitrary = dlsym(handle, "IndigoHIDMessageForHIDArbitrary").map {
      unsafeBitCast($0, to: HIDArbitraryFunc.self)
    }
    key = dlsym(handle, "IndigoHIDMessageForKeyboardArbitrary").map {
      unsafeBitCast($0, to: KeyFunc.self)
    }

    guard
      let clientClass = NSClassFromString("_TtC12SimulatorKit24SimDeviceLegacyHIDClient"),
      let initializer = class_getMethodImplementation(
        clientClass, NSSelectorFromString("initWithDevice:error:"))
    else { throw SimulatorError("Simulator HID client is unavailable") }
    typealias InitFunc = @convention(c) (
      AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>
    ) -> AnyObject?
    var error: NSError?
    let object = unsafeBitCast(initializer, to: InitFunc.self)(
      clientClass.alloc(), NSSelectorFromString("initWithDevice:error:"), device, &error)
    if let error { throw error }
    guard let client = object as? NSObject else { throw SimulatorError("HID client init failed") }
    self.client = client
    self.device = device
    self.udid = udid
  }

  private func send(_ message: UnsafeMutableRawPointer) {
    let selector = NSSelectorFromString(
      "sendWithMessage:freeWhenDone:completionQueue:completion:")
    guard
      let implementation = class_getMethodImplementation(object_getClass(client)!, selector)
    else {
      free(message)
      return
    }
    unsafeBitCast(implementation, to: SendFunc.self)(
      client, selector, message, ObjCBool(true), nil, nil)
  }

  /// [x]/[y] normalized 0..1. Down and move are both event type 1; up is 2.
  func touch(phase: String, x: Double, y: Double) {
    queue.async { [self] in
      var point = CGPoint(x: x, y: y)
      let type: Int32 = phase == "up" ? 2 : 1
      if let message = mouse(&point, nil, 0x32, type, 1, 1, 0) { send(message) }
    }
  }

  func press(_ name: String) {
    queue.async { [self] in
      switch name {
      case "home":
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "launch", udid, "com.apple.springboard"]
        try? process.run()
      case "lock":
        pressButton(source: 0x1)
      case "recents":
        pressButton(source: 0x0)
        Thread.sleep(forTimeInterval: 0.15)
        pressButton(source: 0x0)
      case "volumeUp":
        pressHID(page: 12, usage: 233)
      case "volumeDown":
        pressHID(page: 12, usage: 234)
      default:
        break
      }
    }
  }

  /// Keeps [orientation] in step with the display so a rotation done in
  /// Simulator.app does not leave the next rotate pointing the wrong way.
  func setSize(width: Int, height: Int) {
    queue.async { [self] in
      let portrait = height >= width
      if portrait != (orientation <= 2) { orientation = portrait ? 1 : 3 }
    }
  }

  /// Turns the device a quarter turn clockwise.
  func rotate() -> Bool {
    queue.sync { [self] () -> Bool in
      let next: UInt32
      switch orientation {
      case 1: next = 3
      case 3: next = 2
      case 2: next = 4
      default: next = 1
      }
      guard sendOrientation(next) else { return false }
      orientation = next
      return true
    }
  }

  /// A device-orientation GSEvent to `PurpleWorkspacePort`, the same path
  /// Simulator.app uses; it works with the Simulator window closed.
  private func sendOrientation(_ orientation: UInt32) -> Bool {
    let selector = NSSelectorFromString("lookup:error:")
    typealias LookupFunc = @convention(c) (
      AnyObject, Selector, NSString, AutoreleasingUnsafeMutablePointer<NSError?>
    ) -> mach_port_t
    guard
      let implementation = class_getMethodImplementation(object_getClass(device)!, selector)
    else { return false }
    var lookupError: NSError?
    let port = unsafeBitCast(implementation, to: LookupFunc.self)(
      device, selector, "PurpleWorkspacePort" as NSString, &lookupError)
    guard port != 0 else { return false }
    _ = lookupError

    var buffer = [UInt8](repeating: 0, count: 112)
    return buffer.withUnsafeMutableBufferPointer { pointer -> Bool in
      let base = UnsafeMutableRawPointer(pointer.baseAddress!)
      let header = base.assumingMemoryBound(to: mach_msg_header_t.self)
      header.pointee.msgh_bits = mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND)
      header.pointee.msgh_size = 108
      header.pointee.msgh_remote_port = port
      header.pointee.msgh_local_port = mach_port_t(MACH_PORT_NULL)
      header.pointee.msgh_voucher_port = mach_port_t(MACH_PORT_NULL)
      header.pointee.msgh_id = 0x7B
      base.storeBytes(of: UInt32(50) | UInt32(0x20000), toByteOffset: 0x18, as: UInt32.self)
      base.storeBytes(of: UInt32(4), toByteOffset: 0x48, as: UInt32.self)
      base.storeBytes(of: orientation, toByteOffset: 0x4C, as: UInt32.self)
      return mach_msg_send(header) == KERN_SUCCESS
    }
  }

  /// Types [text] as US-layout key presses; other characters are skipped.
  func type(_ text: String) {
    queue.async { [self] in
      guard let key else { return }
      for character in text {
        guard let (usage, shift) = Self.usage(for: character) else { continue }
        let keys: [UInt32] = shift ? [225, usage] : [usage]
        for code in keys { if let message = key(code, 1) { send(message) } }
        for code in keys.reversed() { if let message = key(code, 2) { send(message) } }
        Thread.sleep(forTimeInterval: 0.02)
      }
    }
  }

  private static let special: [UInt32: UInt32] = [
    0x08: 42, 0x7f: 42, 0x1b: 41,
    0xF700: 82, 0xF701: 81, 0xF702: 80, 0xF703: 79,
    0xF728: 76, 0xF729: 74, 0xF72B: 77,
    0xF72C: 75, 0xF72D: 78,
  ]

  private static func usage(for character: Character) -> (UInt32, Bool)? {
    if let scalar = character.unicodeScalars.first, let usage = special[scalar.value] {
      return (usage, false)
    }
    guard let ascii = character.asciiValue else { return nil }
    switch ascii {
    case 97...122: return (UInt32(ascii - 97) + 4, false)
    case 65...90: return (UInt32(ascii - 65) + 4, true)
    case 49...57: return (UInt32(ascii - 49) + 30, false)
    case 48: return (39, false)
    default: break
    }
    let plain: [Character: UInt32] = [
      "\n": 40, "\t": 43, " ": 44, "-": 45, "=": 46, "[": 47, "]": 48, "\\": 49,
      ";": 51, "'": 52, "`": 53, ",": 54, ".": 55, "/": 56,
    ]
    let shifted: [Character: UInt32] = [
      "!": 30, "@": 31, "#": 32, "$": 33, "%": 34, "^": 35, "&": 36, "*": 37,
      "(": 38, ")": 39, "_": 45, "+": 46, "{": 47, "}": 48, "|": 49, ":": 51,
      "\"": 52, "~": 53, "<": 54, ">": 55, "?": 56,
    ]
    if let usage = plain[character] { return (usage, false) }
    if let usage = shifted[character] { return (usage, true) }
    return nil
  }

  private func pressButton(source: Int32) {
    guard let button else { return }
    for direction: Int32 in [1, 2] {
      if let message = button(source, direction, 0x33) { send(message) }
    }
  }

  private func pressHID(page: UInt32, usage: UInt32) {
    guard let hidArbitrary else { return }
    for direction: UInt32 in [1, 2] {
      if let message = hidArbitrary(0x32, page, usage, direction) { send(message) }
      Thread.sleep(forTimeInterval: 0.05)
    }
  }
}
