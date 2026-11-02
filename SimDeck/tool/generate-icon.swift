// Generates SimDeck's app icon and sidebar mark. Run from SimDeck/:
//
//   swift tool/generate-icon.swift
//
// Writes Resources/Assets.xcassets/AppIcon.appiconset and Resources/logo.png.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("Resources/Assets.xcassets")
let iconset = out.appendingPathComponent("AppIcon.appiconset")

let accent = CGColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 1)
let accentDark = CGColor(red: 0.051, green: 0.580, blue: 0.549, alpha: 1)
let ink = CGColor(red: 0.016, green: 0.125, blue: 0.110, alpha: 1)

func draw(_ ctx: CGContext, transparent: Bool) {
  let body = CGRect(x: 64, y: 64, width: 896, height: 896)
  let squircle = CGPath(
    roundedRect: body, cornerWidth: 200, cornerHeight: 200, transform: nil)

  if !transparent {
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let background = CGGradient(
      colorsSpace: nil,
      colors: [
        CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1),
        CGColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1),
      ] as CFArray,
      locations: [0, 1])!
    ctx.drawLinearGradient(
      background,
      start: CGPoint(x: 512, y: 960), end: CGPoint(x: 512, y: 64), options: [])

    let glow = CGGradient(
      colorsSpace: nil,
      colors: [
        CGColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 0.30),
        CGColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 0),
      ] as CFArray,
      locations: [0, 1])!
    ctx.drawRadialGradient(
      glow, startCenter: CGPoint(x: 512, y: 360), startRadius: 0,
      endCenter: CGPoint(x: 512, y: 360), endRadius: 540, options: [])
    ctx.restoreGState()

    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(6)
    ctx.strokePath()
  }

  // The screen.
  let screen = CGRect(x: 330, y: 220, width: 364, height: 584)
  let screenPath = CGPath(
    roundedRect: screen, cornerWidth: 84, cornerHeight: 84, transform: nil)
  ctx.saveGState()
  ctx.addPath(screenPath)
  ctx.clip()
  let glass = CGGradient(
    colorsSpace: nil, colors: [accent, accentDark] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(
    glass, start: CGPoint(x: 512, y: 804), end: CGPoint(x: 512, y: 220),
    options: [])
  ctx.restoreGState()
  ctx.addPath(screenPath)
  ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.22))
  ctx.setLineWidth(8)
  ctx.strokePath()

  // Camera pill, so the rectangle reads as a phone screen.
  let pill = CGPath(
    roundedRect: CGRect(x: 468, y: 738, width: 88, height: 26),
    cornerWidth: 13, cornerHeight: 13, transform: nil)
  ctx.addPath(pill)
  ctx.setFillColor(CGColor(red: 0.016, green: 0.125, blue: 0.110, alpha: 0.85))
  ctx.fillPath()

  // Play triangle.
  let play = CGMutablePath()
  play.move(to: CGPoint(x: 462, y: 566))
  play.addLine(to: CGPoint(x: 462, y: 458))
  play.addLine(to: CGPoint(x: 576, y: 512))
  play.closeSubpath()
  ctx.addPath(play)
  ctx.setFillColor(ink)
  ctx.fillPath()

  // Broadcast arcs from the screen's top-right corner.
  ctx.setLineCap(.round)
  for (radius, alpha, width) in [(104.0, 0.95, 18.0), (172.0, 0.45, 18.0)] {
    ctx.setStrokeColor(
      CGColor(red: 0.176, green: 0.831, blue: 0.749, alpha: alpha))
    ctx.setLineWidth(width)
    ctx.addArc(
      center: CGPoint(x: 676, y: 792), radius: radius,
      startAngle: 0, endAngle: .pi * 0.42, clockwise: false)
    ctx.strokePath()
  }
}

func png(size: Int, transparent: Bool) -> Data? {
  let space = CGColorSpaceCreateDeviceRGB()
  guard
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8,
      bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }
  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)
  let scale = CGFloat(size) / 1024.0
  context.scaleBy(x: scale, y: scale)
  draw(context, transparent: transparent)
  guard let image = context.makeImage() else { return nil }
  return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

try? FileManager.default.createDirectory(
  at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in variants {
  guard let data = png(size: size, transparent: false) else {
    fatalError("could not render \(name)")
  }
  try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let contents: [String: Any] = [
  "images": [
    ["idiom": "mac", "size": "16x16", "scale": "1x", "filename": "icon_16x16.png"],
    ["idiom": "mac", "size": "16x16", "scale": "2x", "filename": "icon_16x16@2x.png"],
    ["idiom": "mac", "size": "32x32", "scale": "1x", "filename": "icon_32x32.png"],
    ["idiom": "mac", "size": "32x32", "scale": "2x", "filename": "icon_32x32@2x.png"],
    ["idiom": "mac", "size": "128x128", "scale": "1x", "filename": "icon_128x128.png"],
    ["idiom": "mac", "size": "128x128", "scale": "2x", "filename": "icon_128x128@2x.png"],
    ["idiom": "mac", "size": "256x256", "scale": "1x", "filename": "icon_256x256.png"],
    ["idiom": "mac", "size": "256x256", "scale": "2x", "filename": "icon_256x256@2x.png"],
    ["idiom": "mac", "size": "512x512", "scale": "1x", "filename": "icon_512x512.png"],
    ["idiom": "mac", "size": "512x512", "scale": "2x", "filename": "icon_512x512@2x.png"],
  ],
  "info": ["author": "xcode", "version": 1],
]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted])
  .write(to: iconset.appendingPathComponent("Contents.json"))

let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted])
  .write(to: out.appendingPathComponent("Contents.json"))

// Sidebar mark: the same drawing without the squircle background.
if let mark = png(size: 512, transparent: true) {
  try mark.write(to: root.appendingPathComponent("Resources/logo.png"))
}

print("wrote icon set and logo")
