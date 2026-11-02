import SwiftUI
import UniformTypeIdentifiers

/// Lays the open streams out like SimUtil: a grid sized by the window, or a
/// spotlight with the rest in a strip on the right / along the bottom.
struct StreamGridView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  private static let padding: CGFloat = 16
  private static let spacing: CGFloat = 16
  private static let minTileHeight: CGFloat = 320

  var body: some View {
    GeometryReader { geometry in
      let devices = model.openDevices
      if devices.isEmpty {
        emptyState
          .frame(width: geometry.size.width, height: geometry.size.height)
      } else {
        switch model.layout {
        case .grid:
          grid(devices: devices, size: geometry.size)
        case .spotlightVertical:
          spotlight(devices: devices, size: geometry.size, vertical: true)
        case .spotlightHorizontal:
          spotlight(devices: devices, size: geometry.size, vertical: false)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(t.page)
  }

  // MARK: - Grid

  private func grid(devices: [Device], size: CGSize) -> some View {
    let availableWidth = max(size.width - Self.padding * 2, 1)
    let availableHeight = max(size.height - Self.padding, 1)
    let minTileWidth: CGFloat = 300
    let maxColumns = max(
      1,
      Int((availableWidth + Self.spacing) / (minTileWidth + Self.spacing)))
    let columns = min(devices.count, maxColumns)
    let rows = Int(ceil(Double(devices.count) / Double(columns)))
    let tileWidth = (availableWidth - Self.spacing * CGFloat(columns - 1))
      / CGFloat(columns)
    let fittedHeight = (availableHeight - Self.spacing * CGFloat(rows - 1))
      / CGFloat(rows)
    let tileHeight = max(Self.minTileHeight, fittedHeight)
    let contentHeight = CGFloat(rows) * tileHeight
      + Self.spacing * CGFloat(rows - 1) + Self.padding

    return ScrollView {
      VStack(spacing: Self.spacing) {
        ForEach(0..<rows, id: \.self) { row in
          HStack(spacing: Self.spacing) {
            ForEach(0..<columns, id: \.self) { column in
              let index = row * columns + column
              if index < devices.count {
                let device = devices[index]
                StreamTileView(
                  device: device, mode: .grid, draggable: devices.count > 1
                )
                .frame(width: tileWidth, height: tileHeight)
                // The grid is built from positions, so a tile that changes
                // place would otherwise keep its old NSView (and the
                // previous device's video layer).
                .id(device.key)
                .onDrop(
                  of: [.plainText],
                  delegate: TileDropDelegate(targetKey: device.key, model: model))
              } else {
                Color.clear
                  .frame(width: tileWidth, height: tileHeight)
              }
            }
          }
        }
      }
      .padding(.leading, Self.padding)
      .padding(.trailing, Self.padding)
      .padding(.bottom, Self.padding)
      .frame(minHeight: size.height, alignment: .top)
    }
    .scrollDisabled(contentHeight <= size.height)
  }

  // MARK: - Spotlight

  private func spotlight(
    devices: [Device], size: CGSize, vertical: Bool
  ) -> some View {
    let availableWidth = max(size.width - Self.padding * 2, 1)
    let availableHeight = max(size.height - Self.padding, 1)
    let ids = devices.map(\.key)
    let focusKey = model.spotlightKey.flatMap { ids.contains($0) ? $0 : nil }
      ?? ids[0]
    let focus = devices.first { $0.key == focusKey } ?? devices[0]
    let others = devices.filter { $0.key != focusKey }

    return Group {
      if vertical {
        let stripWidth = min(300, max(availableWidth * 0.3, 200))
        let mainWidth = availableWidth
          - (others.isEmpty ? 0 : stripWidth + Self.spacing)
        let thumbHeight = others.isEmpty
          ? 0
          : (availableHeight - Self.spacing * CGFloat(others.count - 1))
            / CGFloat(others.count)
        HStack(alignment: .top, spacing: Self.spacing) {
          StreamTileView(device: focus, mode: .spotlight)
            .frame(width: mainWidth, height: availableHeight)
          if !others.isEmpty {
            VStack(spacing: Self.spacing) {
              ForEach(others) { device in
                StreamTileView(device: device, mode: .thumbnail)
                  .frame(width: stripWidth, height: thumbHeight)
                  .onTapGesture { model.spotlight(device) }
              }
            }
            .frame(width: stripWidth)
          }
        }
        .padding(.leading, Self.padding)
        .padding(.trailing, Self.padding)
        .padding(.bottom, Self.padding)
      } else {
        let stripHeight = min(220, max(availableHeight * 0.3, 160))
        let mainHeight = availableHeight
          - (others.isEmpty ? 0 : stripHeight + Self.spacing)
        let thumbWidth = others.isEmpty
          ? 0
          : (availableWidth - Self.spacing * CGFloat(others.count - 1))
            / CGFloat(others.count)
        VStack(spacing: Self.spacing) {
          StreamTileView(device: focus, mode: .spotlight)
            .frame(width: availableWidth, height: mainHeight)
          if !others.isEmpty {
            HStack(spacing: Self.spacing) {
              ForEach(others) { device in
                StreamTileView(device: device, mode: .thumbnail)
                  .frame(width: thumbWidth, height: stripHeight)
                  .onTapGesture { model.spotlight(device) }
              }
            }
            .frame(width: availableWidth)
          }
        }
        .padding(.leading, Self.padding)
        .padding(.trailing, Self.padding)
        .padding(.bottom, Self.padding)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 0) {
      RoundedRectangle(cornerRadius: SimuTokens.radiusLarge)
        .fill(t.panel)
        .overlay(
          RoundedRectangle(cornerRadius: SimuTokens.radiusLarge)
            .strokeBorder(t.border, lineWidth: 1))
        .frame(width: 48, height: 48)
        .overlay {
          Image(systemName: "play.rectangle")
            .font(.system(size: 22))
            .foregroundStyle(t.textFaint)
        }
      Text("No streams yet")
        .font(t.title)
        .foregroundStyle(t.text)
        .padding(.top, 14)
      Text("Start or stream a device from the sidebar.")
        .font(t.caption)
        .foregroundStyle(t.textMuted)
        .padding(.top, 6)
    }
  }
}

/// Reorders a grid tile when another one is dropped on it.
struct TileDropDelegate: DropDelegate {
  let targetKey: String
  let model: AppModel

  func performDrop(info: DropInfo) -> Bool {
    guard let provider = info.itemProviders(for: [.plainText]).first else {
      return false
    }
    provider.loadObject(ofClass: NSString.self) { value, _ in
      guard let key = value as? String else { return }
      Task { @MainActor in
        model.moveStream(key, before: targetKey)
      }
    }
    return true
  }
}
