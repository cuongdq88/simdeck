import SwiftUI

/// A header control; the header keeps the highest-priority ones that fit and
/// puts the rest in a "more" menu.
struct TileAction: Identifiable {
  let id: String
  let icon: String
  let label: String
  let priority: Int
  var isNav = false
  var active = false
  var color: Color?
  var action: (() -> Void)?

  static let buttonWidth: CGFloat = 27
  static let dividerWidth: CGFloat = 9

  static func fit(_ actions: [TileAction], budget: CGFloat) -> [TileAction] {
    let ranked = actions.sorted { $0.priority > $1.priority }
    for count in stride(from: ranked.count, through: 1, by: -1) {
      let kept = Set(ranked.prefix(count).map(\.id))
      let keptActions = actions.filter { kept.contains($0.id) }
      let hasDivider = keptActions.contains(where: \.isNav)
        && keptActions.contains { !$0.isNav }
      let buttons = CGFloat(count + (count < ranked.count ? 1 : 0))
      let width = buttons * buttonWidth + (hasDivider ? dividerWidth : 0)
      if width <= budget { return keptActions }
    }
    return []
  }
}

struct StreamTileView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  let device: Device

  @FocusState private var keyboardFocused: Bool

  private var session: DeviceSession? { model.session(for: device) }
  private var live: Bool { session?.status.isLive == true }

  var body: some View {
    VStack(spacing: 0) {
      header
      bodyContent
    }
    .background(
      RoundedRectangle(cornerRadius: SimuTokens.radiusLarge)
        .fill(t.panel))
    .overlay(
      RoundedRectangle(cornerRadius: SimuTokens.radiusLarge)
        .strokeBorder(t.border, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: SimuTokens.radiusLarge))
    .padding(1.5)
    .background(
      RoundedRectangle(cornerRadius: SimuTokens.radiusLarge + 1.5)
        .fill(keyboardFocused ? t.accent : .clear))
    .focusable()
    .focused($keyboardFocused)
    .focusEffectDisabled()
    .onKeyPress(phases: .down) { press in
      guard keyboardFocused, let session, session.status.isLive else { return .ignored }
      guard !press.characters.isEmpty else { return .ignored }
      session.typeText(press.characters)
      return .handled
    }
  }

  // MARK: - Header

  private var header: some View {
    GeometryReader { geometry in
      let actions = tileActions
      let kept = TileAction.fit(actions, budget: geometry.size.width - 16 - 90)
      let keptIDs = Set(kept.map(\.id))
      let hidden = actions.filter { !keptIDs.contains($0.id) }

      HStack(spacing: 0) {
        SimuStatusDot(color: statusColor)
          .padding(.trailing, 9)

        HStack(spacing: 8) {
          Text(device.name)
            .font(t.label)
            .foregroundStyle(t.text)
            .lineLimit(1)
            .truncationMode(.tail)
          let fps = model.fps(for: device)
          if model.isRecording(device), let start = model.recordingStart(device) {
            HStack(spacing: 4) {
              Circle().fill(t.danger).frame(width: 6, height: 6)
              Text(elapsed(since: start))
                .font(t.monoSmall)
                .foregroundStyle(t.danger)
            }
            .lineLimit(1)
          } else if fps > 0 {
            Text("\(Int(fps.rounded())) fps")
              .font(t.monoSmall)
              .foregroundStyle(live && fps < 20 ? t.warning : t.textFaint)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

        ForEach(Array(kept.enumerated()), id: \.element.id) { index, action in
          if index > 0, kept[index - 1].isNav, !action.isNav {
            SimuToolbarDivider()
          }
          SimuIconButton(
            icon: action.icon, help: action.label, size: 15,
            active: action.active, color: action.color, action: action.action)
        }

        if !hidden.isEmpty && !kept.isEmpty {
          Menu {
            ForEach(hidden) { action in
              Button {
                action.action?()
              } label: {
                Label(action.label, systemImage: action.icon)
              }
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 15))
              .foregroundStyle(t.textMuted)
              .frame(width: 27, height: 27)
          }
          .menuStyle(.borderlessButton)
          .frame(width: 27)
        }
      }
      .padding(.leading, 14)
      .padding(.trailing, 6)
      .frame(height: 44)
    }
    .frame(height: 44)
    .overlay(alignment: .bottom) {
      Rectangle().fill(t.border).frame(height: 1)
    }
  }

  // MARK: - Body

  private var bodyContent: some View {
    GeometryReader { geometry in
      ZStack {
        if let session, session.status.isLive {
          DeviceFrameView(
            formFactor: DeviceFormFactor.of(device),
            screenSize: session.size,
            maxHeight: geometry.size.height - 16,
            enabled: model.showFrame(device),
            onButton: { button in session.press(button) },
            content: TouchSurface(session: session))
        } else if let message = model.sessionErrors[device.key] ?? failedMessage(session) {
          failedState(message)
        } else {
          connectingState
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private func failedState(_ message: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 20))
        .foregroundStyle(t.danger)
      Text(message)
        .font(t.caption)
        .foregroundStyle(t.textMuted)
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .truncationMode(.tail)
        .padding(.horizontal, 16)
    }
    .padding(16)
  }

  private var connectingState: some View {
    HStack(spacing: 10) {
      SimuSpinner()
      Text("connecting…")
        .font(t.mono)
        .foregroundStyle(t.textMuted)
    }
  }

  private func failedMessage(_ session: DeviceSession?) -> String? {
    guard let session, case .failed(let message) = session.status else { return nil }
    return message
  }

  // MARK: - Actions

  private var tileActions: [TileAction] {
    var actions: [TileAction] = []
    let session = self.session

    for button in [DeviceButton.back, .home, .recents] {
      actions.append(
        TileAction(
          id: button.rawValue,
          icon: buttonSymbol(button),
          label: buttonLabel(button),
          priority: 1,
          isNav: true,
          action: live ? { session?.press(button) } : nil))
    }

    actions.append(
      TileAction(
        id: "keyboard",
        icon: keyboardFocused ? "keyboard" : "keyboard.badge.ellipsis",
        label: keyboardFocused
          ? "Keyboard goes to this device (click to stop)"
          : "Send keyboard to this device",
        priority: 4,
        active: keyboardFocused,
        action: live ? { keyboardFocused.toggle() } : nil))

    actions.append(
      TileAction(
        id: "rotate",
        icon: "rotate.right",
        label: "Rotate screen",
        priority: 4,
        action: live ? { session?.rotate() } : nil))

    actions.append(
      TileAction(
        id: "screenshot",
        icon: "camera",
        label: "Screenshot",
        priority: 4,
        action: live ? { Task { await model.takeScreenshot(device) } } : nil))

    let recording = model.isRecording(device)
    actions.append(
      TileAction(
        id: "record",
        icon: recording ? "stop.circle" : "video",
        label: recording ? "Stop recording" : "Record screen",
        priority: 5,
        color: recording ? t.danger : nil,
        action: live ? { Task { await model.toggleRecording(device) } } : nil))

    let framed = model.showFrame(device)
    actions.append(
      TileAction(
        id: "frame",
        icon: framed ? "iphone" : "iphone.slash",
        label: framed ? "Hide device frame" : "Show device frame",
        priority: 2,
        active: framed,
        action: { model.toggleFrame(device) }))

    if !device.isPhysical {
      actions.append(
        TileAction(
          id: "shutdown",
          icon: "power",
          label: "Shut down device",
          priority: 3,
          action: { Task { await model.stop(device) } }))
    }

    actions.append(
      TileAction(
        id: "close",
        icon: "xmark",
        label: "Close stream",
        priority: 7,
        action: { model.closeStream(device) }))

    return actions
  }

  private func buttonSymbol(_ button: DeviceButton) -> String {
    switch button {
    case .back: return "arrow.left"
    case .home: return "circle"
    case .recents: return "square.on.square"
    case .lock: return "lock"
    case .volumeUp: return "speaker.plus"
    case .volumeDown: return "speaker.minus"
    }
  }

  private func buttonLabel(_ button: DeviceButton) -> String {
    switch button {
    case .back: return "Back"
    case .home: return "Home"
    case .recents: return "Recent apps"
    case .lock: return "Lock screen"
    case .volumeUp: return "Volume up"
    case .volumeDown: return "Volume down"
    }
  }

  private var statusColor: Color {
    if model.sessionErrors[device.key] != nil { return t.danger }
    if let session {
      switch session.status {
      case .live: return t.success
      case .failed: return t.danger
      case .connecting: return t.warning
      }
    }
    return t.warning
  }

  private func elapsed(since start: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(start)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

/// Sends normalized touches to the session; the video fills the framed area
/// so the coordinates map one to one onto the device screen.
struct TouchSurface: View {
  let session: DeviceSession

  @State private var isDown = false

  var body: some View {
    GeometryReader { geometry in
      VideoLayerView(sink: session.sink)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let point = normalized(value.location, in: geometry.size)
              if isDown {
                session.touch(.move, x: point.x, y: point.y)
              } else {
                isDown = true
                session.touch(.down, x: point.x, y: point.y)
              }
            }
            .onEnded { value in
              isDown = false
              let point = normalized(value.location, in: geometry.size)
              session.touch(.up, x: point.x, y: point.y)
            })
    }
  }

  private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
    guard size.width > 0, size.height > 0 else { return .zero }
    return CGPoint(
      x: min(max(point.x / size.width, 0), 1),
      y: min(max(point.y / size.height, 0), 1))
  }
}
