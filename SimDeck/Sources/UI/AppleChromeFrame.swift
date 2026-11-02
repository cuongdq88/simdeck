import SwiftUI

/// Draws Apple's Simulator frame around the live screen, clipped to the
/// screen shape and its notch mask, with clickable side buttons.
struct AppleChromeFrame<Content: View>: View {
  private let chrome: AppleChrome
  private let maxHeight: CGFloat
  private let onButton: ((DeviceButton) -> Void)?
  private let content: Content

  init(
    chrome: AppleChrome, maxHeight: CGFloat,
    onButton: ((DeviceButton) -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.chrome = chrome
    self.maxHeight = maxHeight
    self.onButton = onButton
    self.content = content()
  }

  var body: some View {
    GeometryReader { geometry in
      let padding = chrome.padding.boosted(by: 4)
      let frame = CGSize(
        width: chrome.body.width + padding.left + padding.right,
        height: chrome.body.height + padding.top + padding.bottom)
      let scale = min(
        geometry.size.width / max(frame.width, 1),
        min(geometry.size.height, maxHeight) / max(frame.height, 1))
      let scaled = CGSize(width: frame.width * scale, height: frame.height * scale)

      ZStack(alignment: .topLeading) {
        ForEach(chrome.inputs.filter { !$0.onTop }) { input in
          sideButton(input, padding: padding)
        }

        bodyView
          .frame(width: chrome.body.width, height: chrome.body.height)
          .offset(x: padding.left, y: padding.top)

        ForEach(chrome.inputs.filter(\.onTop)) { input in
          sideButton(input, padding: padding)
        }
      }
      .frame(width: frame.width, height: frame.height, alignment: .topLeading)
      .scaleEffect(scale, anchor: .topLeading)
      .frame(width: scaled.width, height: scaled.height, alignment: .topLeading)
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private var bodyView: some View {
    ZStack {
      if let composite = chrome.composite {
        Image(nsImage: composite)
          .resizable()
          .interpolation(.high)
      } else if let nineSlice = chrome.nineSlice {
        Image(nsImage: nineSlice)
          .resizable(
            capInsets: EdgeInsets(
              top: chrome.corner.height, leading: chrome.corner.width,
              bottom: chrome.corner.height, trailing: chrome.corner.width),
            resizingMode: .stretch)
          .interpolation(.high)
      }

      screenView
        .frame(width: chrome.screen.width, height: chrome.screen.height)
    }
    .frame(width: chrome.body.width, height: chrome.body.height)
  }

  private var screenView: some View {
    content
      .frame(width: chrome.screen.width, height: chrome.screen.height)
      .mask {
        if let mask = chrome.mask {
          Image(nsImage: mask)
            .resizable()
            .interpolation(.high)
        } else {
          Color.white
        }
      }
      .clipShape(
        RoundedRectangle(cornerRadius: chrome.screenRadius, style: .continuous))
  }

  private func sideButton(_ input: AppleChromeInput, padding: NSEdgeInsets) -> some View {
    let rect = input.rect(in: chrome.body, padding: padding)
    return Button {
      if let button = input.button { onButton?(button) }
    } label: {
      Image(nsImage: input.image)
        .resizable()
        .interpolation(.high)
    }
    .buttonStyle(.plain)
    .frame(width: input.size.width, height: input.size.height)
    .offset(x: rect.minX, y: rect.minY)
    .disabled(input.button == nil || onButton == nil)
    .help(sideButtonLabel(input))
  }

  private func sideButtonLabel(_ input: AppleChromeInput) -> String {
    switch input.button {
    case .volumeUp: return "Volume up"
    case .volumeDown: return "Volume down"
    case .lock: return "Lock"
    default: return input.name
    }
  }
}
