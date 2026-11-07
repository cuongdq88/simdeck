import SwiftUI

@main
struct SimDeckApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .task { await model.start() }
        .frame(minWidth: 1020, minHeight: 680)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1360, height: 860)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { model.settingsSheetShown = true }
          .keyboardShortcut(",", modifiers: [.command])
      }
      CommandMenu("Device") {
        Button("New device…") { model.createSheetShown = true }
          .keyboardShortcut("n", modifiers: [.command])
        Button("Refresh") { Task { await model.refresh() } }
          .keyboardShortcut("r", modifiers: [.command])
      }
    }
  }
}
