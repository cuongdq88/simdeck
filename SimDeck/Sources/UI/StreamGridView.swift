import SwiftUI

/// Lays the open streams out like SimUtil's grid: the tiles fill the area
/// under the top bar, one stream takes the whole width, and the grid scrolls
/// only when the rows would get too short to use.
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
        let availableWidth = max(geometry.size.width - Self.padding * 2, 1)
        let availableHeight = max(geometry.size.height - Self.padding, 1)
        let columns = devices.count == 1 ? 1 : (availableWidth >= 760 ? 2 : 1)
        let rows = Int(ceil(Double(devices.count) / Double(columns)))
        let tileWidth = (availableWidth - Self.spacing * CGFloat(columns - 1))
          / CGFloat(columns)
        let fittedHeight = (availableHeight - Self.spacing * CGFloat(rows - 1))
          / CGFloat(rows)
        let tileHeight = max(Self.minTileHeight, fittedHeight)
        let contentHeight = CGFloat(rows) * tileHeight
          + Self.spacing * CGFloat(rows - 1) + Self.padding

        ScrollView {
          VStack(spacing: Self.spacing) {
            ForEach(0..<rows, id: \.self) { row in
              HStack(spacing: Self.spacing) {
                ForEach(0..<columns, id: \.self) { column in
                  let index = row * columns + column
                  if index < devices.count {
                    StreamTileView(device: devices[index])
                      .frame(width: tileWidth, height: tileHeight)
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
          .frame(minHeight: geometry.size.height, alignment: .top)
        }
        .scrollDisabled(contentHeight <= geometry.size.height)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(t.page)
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
