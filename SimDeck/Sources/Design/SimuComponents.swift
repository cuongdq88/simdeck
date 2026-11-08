import SwiftUI

// MARK: - Panel

struct SimuPanel<Content: View>: View {
  private let padding: CGFloat
  private let content: Content

  init(padding: CGFloat = 0, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  @Environment(\.simu) private var t

  var body: some View {
    content
      .padding(padding)
      .background(RoundedRectangle(cornerRadius: SimuTokens.radiusLarge).fill(t.panel))
      .overlay(
        RoundedRectangle(cornerRadius: SimuTokens.radiusLarge)
          .strokeBorder(t.border, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: SimuTokens.radiusLarge))
  }
}

// MARK: - Buttons

struct SimuIconButton: View {
  let icon: String
  let help: String
  var size: CGFloat = 16
  var active = false
  var color: Color?
  var action: (() -> Void)?

  @State private var hovered = false
  @Environment(\.simu) private var t
  @Environment(\.simuInToolbar) private var inToolbar

  var body: some View {
    Button {
      action?()
    } label: {
      Image(systemName: icon)
        .font(.system(size: size))
        .foregroundStyle(foreground)
        .frame(width: size, height: size)
        .padding(6)
        .background(
          RoundedRectangle(cornerRadius: inToolbar ? 999 : SimuTokens.radius)
            .fill(background))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .help(help)
    .disabled(action == nil)
  }

  private var enabled: Bool { action != nil }

  private var foreground: Color {
    if !enabled { return t.textFaint }
    if let color { return color }
    if active { return t.accent }
    return hovered ? t.text : t.textMuted
  }

  private var background: Color {
    if active { return t.accent.opacity(0.14) }
    if hovered && enabled { return t.hover }
    return .clear
  }
}

struct SimuButton: View {
  let label: String
  var primary = false
  var icon: String?
  var action: (() -> Void)?

  @State private var hovered = false
  @Environment(\.simu) private var t

  var body: some View {
    Button {
      action?()
    } label: {
      HStack(spacing: 6) {
        if let icon {
          Image(systemName: icon).font(.system(size: 12))
        }
        Text(label).font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(primary ? t.onAccent : t.text)
      .frame(height: 26)
      .padding(.horizontal, 10)
      .background(RoundedRectangle(cornerRadius: SimuTokens.radiusSmall).fill(
        primary ? t.accent : t.raised))
      .overlay(
        RoundedRectangle(cornerRadius: SimuTokens.radiusSmall)
          .strokeBorder(primary ? .clear : t.border, lineWidth: 1))
      .opacity(action == nil ? 0.5 : (hovered ? 0.88 : 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
    .disabled(action == nil)
  }
}

// MARK: - Toolbar

struct SimuToolbar<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  @Environment(\.simu) private var t

  var body: some View {
    HStack(spacing: 0) { content }
      .padding(3)
      .background(RoundedRectangle(cornerRadius: 999).fill(t.panel))
      .overlay(RoundedRectangle(cornerRadius: 999).strokeBorder(t.border, lineWidth: 1))
      .environment(\.simuInToolbar, true)
  }
}

struct SimuToolbarDivider: View {
  @Environment(\.simu) private var t

  var body: some View {
    Rectangle()
      .fill(t.border)
      .frame(width: 1, height: 16)
      .padding(.horizontal, 4)
  }
}

// MARK: - Status

struct SimuStatusDot: View {
  let color: Color
  var size: CGFloat = 7
  var ring: Color?

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
      .overlay {
        if let ring {
          Circle().strokeBorder(ring, lineWidth: 2)
        }
      }
  }
}

struct SimuSpinner: View {
  @Environment(\.simu) private var t

  var body: some View {
    ProgressView()
      .controlSize(.small)
      .scaleEffect(0.75)
      .tint(t.accent)
  }
}

// MARK: - Text field

struct SimuTextField: View {
  @Binding var text: String
  var hint = ""
  var icon: String?
  var monospace = false
  var onSubmit: (() -> Void)?

  @Environment(\.simu) private var t

  var body: some View {
    HStack(spacing: 6) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 14))
          .foregroundStyle(t.textFaint)
      }
      TextField(hint, text: $text)
        .textFieldStyle(.plain)
        .font(monospace ? t.mono : t.body)
        .foregroundStyle(t.text)
        .onSubmit { onSubmit?() }
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 11))
            .foregroundStyle(t.textFaint)
        }
        .buttonStyle(.plain)
        .help("Clear")
      }
    }
    .padding(.leading, icon == nil ? 10 : 8)
    .padding(.trailing, 8)
    .frame(height: 30)
    .background(RoundedRectangle(cornerRadius: SimuTokens.radius).fill(t.raised))
    .overlay(
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .strokeBorder(t.border, lineWidth: 1))
  }
}

// MARK: - Misc

/// Notices in the bottom-right of a window, newest on top. Each one keeps its
/// own row so a burst stacks instead of covering itself.
struct NoticePanel: View {
  let items: [AppModel.NoticeEntry]
  let onDismiss: (UUID) -> Void

  @Environment(\.simu) private var t

  var body: some View {
    VStack(alignment: .trailing, spacing: 8) {
      ForEach(items) { entry in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "bell")
            .font(.system(size: 12))
            .foregroundStyle(t.textMuted)
            .padding(.top, 2)
          VStack(alignment: .leading, spacing: 2) {
            Text(entry.text)
              .font(t.caption)
              .foregroundStyle(t.text)
              .fixedSize(horizontal: false, vertical: true)
            Text(entry.date, format: .dateTime.hour().minute())
              .font(t.monoLabel)
              .foregroundStyle(t.textFaint)
          }
          Spacer(minLength: 4)
          Button {
            onDismiss(entry.id)
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10))
              .foregroundStyle(t.textFaint)
          }
          .buttonStyle(.plain)
          .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: SimuTokens.radius)
            .fill(t.raised))
        .overlay(
          RoundedRectangle(cornerRadius: SimuTokens.radius)
            .strokeBorder(t.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.18), value: items)
  }
}

struct SimuBrandLogo: View {
  var size: CGFloat = 24

  var body: some View {
    Group {
      if let logo = NSImage(named: "logo") {
        Image(nsImage: logo)
          .resizable()
          .interpolation(.medium)
      } else {
        Image(systemName: "display")
          .resizable()
          .scaledToFit()
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel("SimDeck")
  }
}
