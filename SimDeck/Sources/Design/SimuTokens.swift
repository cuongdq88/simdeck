import SwiftUI

/// SimUtil's design tokens, ported one to one so the SwiftUI shell looks the
/// same as the Flutter one.
struct SimuTokens {
  let page: Color
  let sidebar: Color
  let panel: Color
  let raised: Color
  let border: Color
  let hover: Color
  let text: Color
  let textMuted: Color
  let textFaint: Color
  let accent: Color
  let onAccent: Color
  let success: Color
  let danger: Color
  let warning: Color
  let android: Color
  let apple: Color

  static let radiusSmall: CGFloat = 6
  static let radius: CGFloat = 8
  static let radiusLarge: CGFloat = 12

  static let dark = SimuTokens(
    page: Color(hex: 0x0B0C0E),
    sidebar: Color(hex: 0x111215),
    panel: Color(hex: 0x17181B),
    raised: Color(hex: 0x202125),
    border: Color(hex: 0xFFFFFF, alpha: 0x17 / 255),
    hover: Color(hex: 0xFFFFFF, alpha: 0x0F / 255),
    text: Color(hex: 0xF2F3F5),
    textMuted: Color(hex: 0xFFFFFF, alpha: 0x9E / 255),
    textFaint: Color(hex: 0xFFFFFF, alpha: 0x66 / 255),
    accent: Color(hex: 0x2DD4BF),
    onAccent: Color(hex: 0x04201C),
    success: Color(hex: 0x34D399),
    danger: Color(hex: 0xF87171),
    warning: Color(hex: 0xFBBF24),
    android: Color(hex: 0x3DDC84),
    apple: Color(hex: 0x9CC3FF))

  static let light = SimuTokens(
    page: Color(hex: 0xF4F5F7),
    sidebar: Color(hex: 0xECEDF0),
    panel: Color(hex: 0xFFFFFF),
    raised: Color(hex: 0xF0F1F3),
    border: Color(hex: 0x000000, alpha: 0x17 / 255),
    hover: Color(hex: 0x000000, alpha: 0x0D / 255),
    text: Color(hex: 0x121316),
    textMuted: Color(hex: 0x000000, alpha: 0x99 / 255),
    textFaint: Color(hex: 0x000000, alpha: 0x66 / 255),
    accent: Color(hex: 0x0D9488),
    onAccent: Color(hex: 0xFFFFFF),
    success: Color(hex: 0x059669),
    danger: Color(hex: 0xDC2626),
    warning: Color(hex: 0xD97706),
    android: Color(hex: 0x16A34A),
    apple: Color(hex: 0x2563EB))

  static func of(_ scheme: ColorScheme) -> SimuTokens {
    scheme == .dark ? .dark : .light
  }

  var title: Font { .system(size: 15, weight: .semibold) }
  var label: Font { .system(size: 13, weight: .semibold) }
  var body: Font { .system(size: 13) }
  var caption: Font { .system(size: 12) }
  var overline: Font { .system(size: 11, weight: .semibold) }
  var mono: Font { .custom("Menlo", size: 11.5) }
  var monoSmall: Font { .custom("Menlo", size: 11) }
  var monoLabel: Font { .custom("Menlo", size: 10.5) }
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha)
  }
}

private struct SimuTokensKey: EnvironmentKey {
  static let defaultValue = SimuTokens.dark
}

private struct SimuInToolbarKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var simu: SimuTokens {
    get { self[SimuTokensKey.self] }
    set { self[SimuTokensKey.self] = newValue }
  }

  var simuInToolbar: Bool {
    get { self[SimuInToolbarKey.self] }
    set { self[SimuInToolbarKey.self] = newValue }
  }
}
