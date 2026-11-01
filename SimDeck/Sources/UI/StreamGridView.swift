import SwiftUI

struct StreamGridView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  private let columns = [GridItem(.adaptive(minimum: 380, maximum: 900), spacing: 16)]

  var body: some View {
    Group {
      if model.openDevices.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(model.openDevices) { device in
              StreamTileView(device: device)
            }
          }
          .padding(.leading, 16)
          .padding(.trailing, 16)
          .padding(.bottom, 16)
        }
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
