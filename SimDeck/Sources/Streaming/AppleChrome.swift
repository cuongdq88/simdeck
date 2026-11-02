import Cocoa

/// Apple's Simulator device frame for one simulator, read from Xcode's
/// DeviceKit chrome bundles at runtime. Sizes are in points.
struct AppleChrome {
  let body: CGSize
  let screen: CGSize
  let composite: NSImage?
  let nineSlice: NSImage?
  let corner: CGSize
  let outerRadius: CGFloat
  let mask: NSImage?
  let padding: NSEdgeInsets
  let inputs: [AppleChromeInput]
  let drawIsland: Bool

  var frameSize: CGSize {
    CGSize(
      width: body.width + padding.left + padding.right,
      height: body.height + padding.top + padding.bottom)
  }

  /// Corner radius of the screen opening, from the outline radius minus the
  /// thicker bezel side.
  var screenRadius: CGFloat {
    let inset = max(body.width - screen.width, body.height - screen.height)
    return max(0, outerRadius - inset / 2)
  }

  /// Chrome art is drawn in the device's native orientation.
  func matches(videoSize: CGSize) -> Bool {
    (screen.width >= screen.height) == (videoSize.width >= videoSize.height)
  }
}

struct AppleChromeInput: Identifiable {
  let name: String
  let size: CGSize
  let image: NSImage
  let imageDown: NSImage?
  let anchor: String
  let align: String
  let normal: CGPoint
  let rollover: CGPoint
  let onTop: Bool

  var id: String { name }

  var button: DeviceButton? {
    switch name {
    case "volume-up": return .volumeUp
    case "volume-down": return .volumeDown
    case "power", "sleep": return .lock
    default: return nil
    }
  }

  /// Where the button sits in the frame, with the body at `padding`'s
  /// top-left.
  func rect(in body: CGSize, padding: NSEdgeInsets) -> CGRect {
    let g = CGPoint(
      x: 2 * normal.x - rollover.x,
      y: 2 * normal.y - rollover.y)
    let x = align == "trailing"
      ? padding.left + body.width + g.x - size.width
      : padding.left + g.x
    let origin: CGPoint
    switch anchor {
    case "right":
      origin = CGPoint(x: padding.left + body.width + g.x, y: padding.top + g.y)
    case "top":
      origin = CGPoint(x: x, y: padding.top + g.y - size.height)
    case "bottom":
      origin = CGPoint(x: x, y: padding.top + body.height + g.y)
    default:
      origin = CGPoint(
        x: padding.left + rollover.x - size.width / 2,
        y: padding.top + rollover.y)
    }
    return CGRect(origin: origin, size: size)
  }
}

extension NSEdgeInsets {
  /// Side buttons barely show past Apple's body; stick them out a little
  /// further so they read and are easy to click.
  func boosted(by amount: CGFloat) -> NSEdgeInsets {
    NSEdgeInsets(
      top: top > 0 ? top + amount : 0,
      left: left > 0 ? left + amount : 0,
      bottom: bottom > 0 ? bottom + amount : 0,
      right: right > 0 ? right + amount : 0)
  }
}

enum SimChromeLoader {
  static func load(device: NSObject) -> AppleChrome? {
    SimFrameworks.deviceType(of: device).flatMap(load(type:))
  }

  static func load(type: NSObject) -> AppleChrome? {
    guard let bundle = type.value(forKey: "bundlePath") as? String else { return nil }
    let resources = URL(fileURLWithPath: bundle)
      .appendingPathComponent("Contents/Resources")
    guard
      let profile = NSDictionary(
        contentsOf: resources.appendingPathComponent("profile.plist")),
      let chromeId = profile["chromeIdentifier"] as? String,
      let chromeName = chromeId.split(separator: ".").last
    else { return nil }

    let dir = URL(
      fileURLWithPath:
        "/Library/Developer/DeviceKit/Chrome/\(chromeName).devicechrome/Contents/Resources")
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("chrome.json")),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let images = json["images"] as? [String: Any],
      let sizing = images["sizing"] as? [String: Any]
    else { return nil }

    guard let screen = screenSize(type: type) else { return nil }
    let insets = NSEdgeInsets(
      top: number(sizing["topHeight"]),
      left: number(sizing["leftWidth"]),
      bottom: number(sizing["bottomHeight"]),
      right: number(sizing["rightWidth"]))

    let border = (json["paths"] as? [String: Any])?["simpleOutsideBorder"]
      as? [String: Any]
    let outerRadius = number(border?["cornerRadiusX"])

    func art(_ name: String?) -> NSImage? {
      guard let name, !name.isEmpty else { return nil }
      return NSImage(contentsOf: dir.appendingPathComponent("\(name).pdf"))
    }

    var composite: NSImage?
    var body = CGSize(
      width: screen.width + insets.left + insets.right,
      height: screen.height + insets.top + insets.bottom)
    if let image = art(images["composite"] as? String) {
      let fits = abs(image.size.width - body.width) <= 6
        && abs(image.size.height - body.height) <= 6
      if fits {
        composite = render(size: image.size, scale: 3) {
          image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        body = image.size
      }
    }

    var nineSlice: NSImage?
    var corner = CGSize.zero
    if composite == nil,
      let topLeft = art(images["topLeft"] as? String),
      let topRight = art(images["topRight"] as? String),
      let bottomLeft = art(images["bottomLeft"] as? String),
      let bottomRight = art(images["bottomRight"] as? String),
      let top = art(images["top"] as? String),
      let bottom = art(images["bottom"] as? String),
      let left = art(images["left"] as? String),
      let right = art(images["right"] as? String)
    {
      let cw = topLeft.size.width
      let ch = topLeft.size.height
      let size = CGSize(width: cw * 2 + 1, height: ch * 2 + 1)
      nineSlice = render(size: size, scale: 3) {
        topLeft.draw(in: NSRect(x: 0, y: ch + 1, width: cw, height: ch))
        top.draw(in: NSRect(x: cw, y: ch + 1, width: 1, height: ch))
        topRight.draw(in: NSRect(x: cw + 1, y: ch + 1, width: cw, height: ch))
        left.draw(in: NSRect(x: 0, y: ch, width: cw, height: 1))
        right.draw(in: NSRect(x: cw + 1, y: ch, width: cw, height: 1))
        bottomLeft.draw(in: NSRect(x: 0, y: 0, width: cw, height: ch))
        bottom.draw(in: NSRect(x: cw, y: 0, width: 1, height: ch))
        bottomRight.draw(in: NSRect(x: cw + 1, y: 0, width: cw, height: ch))
      }
      corner = CGSize(width: cw, height: ch)
    }

    guard composite != nil || nineSlice != nil else { return nil }

    var mask: NSImage?
    if let maskName = profile["framebufferMask"] as? String,
      let image = art(maskName)
    {
      mask = render(size: image.size, scale: 1) {
        image.draw(in: NSRect(origin: .zero, size: image.size))
      }
    }

    let paddingValues = images["devicePadding"] as? [String: Any] ?? [:]
    let padding = NSEdgeInsets(
      top: number(paddingValues["top"]),
      left: number(paddingValues["left"]),
      bottom: number(paddingValues["bottom"]),
      right: number(paddingValues["right"]))

    let inputs: [AppleChromeInput] = (json["inputs"] as? [[String: Any]] ?? [])
      .compactMap { entry in
        guard let name = entry["name"] as? String,
          let image = art(entry["image"] as? String)
        else { return nil }
        func point(_ values: Any?) -> CGPoint {
          let map = values as? [String: Any] ?? [:]
          return CGPoint(x: number(map["x"]), y: number(map["y"]))
        }
        let offsets = entry["offsets"] as? [String: Any]
        return AppleChromeInput(
          name: name,
          size: image.size,
          image: image,
          imageDown: art(entry["imageDown"] as? String),
          anchor: entry["anchor"] as? String ?? "left",
          align: entry["align"] as? String ?? "leading",
          normal: point(offsets?["normal"]),
          rollover: point(offsets?["rollover"]),
          onTop: entry["onTop"] as? Bool ?? false)
      }

    return AppleChrome(
      body: body,
      screen: screen,
      composite: composite,
      nineSlice: nineSlice,
      corner: corner,
      outerRadius: outerRadius,
      mask: mask,
      padding: padding,
      inputs: inputs,
      // Simulators draw their own Dynamic Island in the framebuffer.
      drawIsland: false)
  }

  private static func screenSize(type: NSObject) -> CGSize? {
    guard let pixels = SimFrameworks.mainScreenSize(type: type) else { return nil }
    let selector = NSSelectorFromString("mainScreenScale")
    guard type.responds(to: selector) else { return pixels }
    typealias GetScale = @convention(c) (AnyObject, Selector) -> Float
    let scale = CGFloat(
      unsafeBitCast(type.method(for: selector), to: GetScale.self)(type, selector))
    guard scale > 0 else { return pixels }
    return CGSize(width: pixels.width / scale, height: pixels.height / scale)
  }

  private static func render(
    size: CGSize, scale: CGFloat, draw: () -> Void
  ) -> NSImage? {
    guard size.width > 0, size.height > 0,
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }

  private static func number(_ value: Any?) -> CGFloat {
    if let value = value as? NSNumber { return CGFloat(value.doubleValue) }
    if let value = value as? Double { return CGFloat(value) }
    return 0
  }
}
