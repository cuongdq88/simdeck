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
    .environment(\.simu, tokens)
    .sheet(isPresented: $model.createSheetShown) {
      CreateDeviceSheet()
        .environment(\.simu, tokens)
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
