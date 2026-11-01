import Cocoa
import CoreVideo
import IOSurface

/// Private CoreSimulator/SimulatorKit entry points, loaded at runtime so the
/// app has no link-time dependency on Xcode's frameworks.
enum SimFrameworks {
  static let developerDir: String = ShellEnv.developerDir

  static let load: Void = {
    let developer = developerDir
    for path in [
      "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
      "\(developer)/Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
      "\(developer)/../SharedFrameworks/SimulatorKit.framework/SimulatorKit",
      "\(developer)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit",
    ] {
      _ = dlopen(path, RTLD_NOW)
    }
  }()

  static func device(udid: String) -> NSObject? {
    _ = load
    guard let contextClass = NSClassFromString("SimServiceContext") as? NSObject.Type,
      let context = contextClass.perform(
        NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"),
        with: developerDir, with: nil)?.takeUnretainedValue() as? NSObject,
      let deviceSet = context.perform(
        NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?
        .takeUnretainedValue() as? NSObject,
      let devices = deviceSet.value(forKey: "devices") as? [NSObject]
    else { return nil }
    return devices.first { ($0.value(forKey: "UDID") as? NSUUID)?.uuidString == udid }
  }

  static func deviceType(of device: NSObject) -> NSObject? {
    let selector = NSSelectorFromString("deviceType")
    guard device.responds(to: selector) else { return nil }
    return device.perform(selector)?.takeUnretainedValue() as? NSObject
  }

  /// Native screen size in pixels from the private `SimDeviceType.mainScreenSize`.
  static func mainScreenSize(_ device: NSObject) -> CGSize? {
    deviceType(of: device).flatMap(mainScreenSize(type:))
  }

  static func mainScreenSize(type: NSObject) -> CGSize? {
    let selector = NSSelectorFromString("mainScreenSize")
    guard type.responds(to: selector) else { return nil }
    typealias GetSize = @convention(c) (AnyObject, Selector) -> CGSize
    let size = unsafeBitCast(type.method(for: selector), to: GetSize.self)(type, selector)
    return size.width > 0 && size.height > 0 ? size : nil
  }
}

@objc protocol FramebufferDescriptor {
  @objc(registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:)
  func registerScreenCallbacks(
    uuid: UUID,
    callbackQueue: DispatchQueue,
    frameCallback: @convention(block) @escaping () -> Void,
    surfacesChangedCallback: @convention(block) @escaping () -> Void,
    propertiesChangedCallback: @convention(block) @escaping () -> Void
  )
}

struct SimulatorError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
