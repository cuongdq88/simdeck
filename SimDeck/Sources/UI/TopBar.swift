import SwiftUI

struct TopBar: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  let sidebarOpen: Bool
  let onToggleSidebar: () -> Void

  @State private var environmentShown = false

  var body: some View {
    HStack {
      SimuIconButton(
        icon: "sidebar.left",
        help: sidebarOpen ? "Hide devices" : "Show devices",
        action: onToggleSidebar)

      Spacer()

      SimuToolbar {
        SimuIconButton(
          icon: "plus",
          help: "New device",
          action: { model.createSheetShown = true })
        SimuIconButton(
          icon: "arrow.clockwise",
          help: "Refresh devices",
          action: { Task { await model.refresh() } })
        SimuToolbarDivider()
        SimuIconButton(
          icon: "stethoscope",
          help: "Environment check",
          action: { environmentShown.toggle() })
          .popover(isPresented: $environmentShown, arrowEdge: .bottom) {
            environment
          }
      }
    }
    .padding(.leading, sidebarOpen ? 10 : 78)
    .padding(.trailing, 16)
    .frame(height: 52)
    .background(t.page)
  }

  private var environment: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Environment").font(.system(size: 13, weight: .semibold))
      row("Android SDK", model.androidHome)
      row("adb", model.adbAvailable ? "found" : "missing")
      row("Emulator", model.emulatorAvailable ? "found" : "missing")
      row("System images", "\(model.images.count)")
      row("Simulators", "\(model.iosSimulators.count)")
    }
    .padding(14)
    .frame(width: 380, alignment: .leading)
  }

  private func row(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(width: 110, alignment: .leading)
      Text(value)
        .font(.custom("Menlo", size: 11))
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
