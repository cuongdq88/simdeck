import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  @State private var sidebarOpen = true

  var body: some View {
    let tokens = SimuTokens.of(colorScheme)
    HStack(spacing: 0) {
      if sidebarOpen {
        SidebarView()
          .frame(width: 288)
          .transition(.move(edge: .leading))
      }
      VStack(spacing: 0) {
        TopBar(sidebarOpen: sidebarOpen) {
          withAnimation(.easeOut(duration: 0.22)) { sidebarOpen.toggle() }
        }
        StreamGridView()
      }
    }
    .background(tokens.page)
    .ignoresSafeArea(.container, edges: .top)
    .environment(\.simu, tokens)
    .sheet(isPresented: $model.createSheetShown) {
      CreateDeviceSheet()
        .environment(\.simu, tokens)
    }
    .sheet(isPresented: $model.sdkSheetShown) {
      SdkManagerSheet()
        .environment(\.simu, tokens)
    }
    .sheet(isPresented: $model.connectSheetShown) {
      ConnectDeviceSheet()
        .environment(\.simu, tokens)
    }
    .sheet(isPresented: $model.settingsSheetShown) {
      SettingsSheet()
        .environment(\.simu, tokens)
    }
    .sheet(
      isPresented: Binding(
        get: { model.logcatDevice != nil },
        set: { if !$0 { model.closeLogcat() } })
    ) {
      if let device = model.logcatDevice {
        LogcatSheet(device: device)
          .environment(\.simu, tokens)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      NoticePanel(items: model.banners, onDismiss: { model.dismissBanner($0) })
        .padding(.bottom, 22)
        .padding(.trailing, 16)
    }
    .alert(
      "SimDeck",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}
