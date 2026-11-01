import SwiftUI

enum DeviceFormFactor {
  case phone
  case tablet
  case tv
  case watch

  static func of(_ device: Device) -> DeviceFormFactor {
    let name = device.name.lowercased()
    if name.contains("tv") || name.contains("television") { return .tv }
    if name.contains("watch") || name.contains("wear") { return .watch }
    if name.contains("ipad") || name.contains("tablet") { return .tablet }
    return .phone
  }

  /// Bezel thickness and screen corner radius as fractions of the screen's
  /// shorter side, like SimUtil's drawn frame.
  var bezelRatio: CGFloat {
    switch self {
    case .phone: return 0.035
    case .tablet: return 0.04
    case .tv: return 0.012
    case .watch: return 0.08
    }
  }

  var radiusRatio: CGFloat {
    switch self {
    case .phone: return 0.11
    case .tablet: return 0.045
    case .tv: return 0
    case .watch: return 0.22
    }
  }

  var hasSideButtons: Bool { self == .phone || self == .tablet }
}

/// A drawn bezel around the live screen, sized to fit the view.
struct DeviceFrameView<Content: View>: View {
  let formFactor: DeviceFormFactor
  let screenSize: CGSize
  let maxHeight: CGFloat
  let enabled: Bool
  let onButton: ((DeviceButton) -> Void)?
  let content: Content

  var body: some View {
    GeometryReader { geometry in
      let availableWidth = max(geometry.size.width, 1)
      let availableHeight = max(min(geometry.size.height, maxHeight), 1)
      let screenWidth = max(screenSize.width, 1)
      let screenHeight = max(screenSize.height, 1)
      let short = min(screenWidth, screenHeight)
      let bezelPerPixel = enabled ? formFactor.bezelRatio * short : 0
      let outerWidth = screenWidth + 2 * bezelPerPixel
      let outerHeight = screenHeight + 2 * bezelPerPixel
      let scale = min(availableWidth / outerWidth, availableHeight / outerHeight)
      let width = screenWidth * scale
      let height = screenHeight * scale
      let bezel = bezelPerPixel * scale
      let radius = enabled ? formFactor.radiusRatio * short * scale : 6
      let frameWidth = width + 2 * bezel
      let frameHeight = height + 2 * bezel

      ZStack {
        if enabled {
          RoundedRectangle(cornerRadius: radius + bezel, style: .continuous)
            .fill(Color(hex: 0x111111))
            .overlay(
              RoundedRectangle(cornerRadius: radius + bezel, style: .continuous)
                .strokeBorder(Color(hex: 0x3A3A3C), lineWidth: 1))
            .frame(width: frameWidth, height: frameHeight)

          content
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

          if formFactor.hasSideButtons, let onButton {
            sideButtons(
              frameHeight: frameHeight, frameWidth: frameWidth,
              scale: scale, short: short, onButton: onButton)
          }
        } else {
          content
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  /// Power above the volume rocker on the right edge, as fractions of the
  /// frame height.
  private func sideButtons(
    frameHeight: CGFloat, frameWidth: CGFloat, scale: CGFloat, short: CGFloat,
    onButton: @escaping (DeviceButton) -> Void
  ) -> some View {
    let depth = max(2.5, 0.018 * short * scale)
    let buttons: [(DeviceButton, CGFloat, CGFloat)] = [
      (.lock, 0.17, 0.25),
      (.volumeUp, 0.30, 0.38),
      (.volumeDown, 0.385, 0.465),
    ]
    return ZStack {
      ForEach(Array(buttons.enumerated()), id: \.offset) { _, entry in
        let (button, top, bottom) = entry
        let buttonHeight = (bottom - top) * frameHeight
        let centerY = -frameHeight / 2 + (top + (bottom - top) / 2) * frameHeight
        Button {
          onButton(button)
        } label: {
          Capsule()
            .fill(Color(hex: 0x2C2C2E))
            .overlay(Capsule().strokeBorder(Color(hex: 0x3A3A3C), lineWidth: 1))
            .frame(width: depth, height: buttonHeight)
        }
        .buttonStyle(.plain)
        .offset(x: frameWidth / 2 - depth / 2 + 1, y: centerY)
        .help(button == .lock ? "Power" : (button == .volumeUp ? "Volume up" : "Volume down"))
      }
    }
  }
}
