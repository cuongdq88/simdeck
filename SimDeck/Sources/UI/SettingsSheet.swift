import AppKit
import SwiftUI

struct SettingsSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          startup
          recording
          view
        }
        .padding(20)
      }
    }
    .frame(width: 560, height: 470)
    .background(t.panel)
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("Settings")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(t.text)
        Text("Defaults for this Mac")
          .font(t.caption)
          .foregroundStyle(t.textMuted)
      }
      Spacer()
      SimuIconButton(icon: "xmark", help: "Close", size: 14) { dismiss() }
    }
    .padding(20)
  }

  private var startup: some View {
    section("Startup") {
      toggle(
        "Start emulators headless",
        isOn: Binding(
          get: { model.headlessDefault },
          set: { model.setHeadlessDefault($0) }),
        hint: "No separate emulator window; the screen still appears in SimDeck. "
          + "Agents always boot headless.")
    }
  }

  private var recording: some View {
    section("Recording") {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text("Folder")
            .font(t.body)
            .foregroundStyle(t.text)
          Spacer(minLength: 8)
          Text(model.recordingDirectory.path)
            .font(t.monoSmall)
            .foregroundStyle(t.textMuted)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
        HStack(spacing: 8) {
          SimuButton(label: "Choose…", icon: "folder") { choose() }
          SimuButton(label: "Default", icon: "arrow.uturn.backward") {
            model.setRecordingFolder("")
          }
          SimuButton(label: "Open in Finder", icon: "arrow.up.right.square") {
            NSWorkspace.shared.open(model.recordingDirectory)
          }
        }
      }
      Text("Screenshots and screen recordings are saved here.")
        .font(t.caption)
        .foregroundStyle(t.textMuted)
      Picker(
        "Grid recording quality",
        selection: Binding(
          get: { model.gridQuality },
          set: { model.setGridQuality($0) })
      ) {
        ForEach(GridRecordQuality.allCases) { quality in
          Text(quality.label).tag(quality)
        }
      }
      .pickerStyle(.menu)
    }
  }

  private var view: some View {
    section("View") {
      Picker(
        "Default layout",
        selection: Binding(
          get: { model.layout },
          set: { model.setLayout($0) })
      ) {
        ForEach(StreamLayout.allCases) { layout in
          Text(layout.label).tag(layout)
        }
      }
      .pickerStyle(.menu)
      toggle(
        "Show device frame",
        isOn: Binding(
          get: { model.frameDefault },
          set: { model.setFrameDefault($0) }),
        hint: "A stream tile's own frame button still overrides this.")
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = model.recordingDirectory
    if panel.runModal() == .OK, let url = panel.url {
      model.setRecordingFolder(url.path)
    }
  }

  private func section<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title.uppercased())
        .font(t.overline)
        .tracking(0.6)
        .foregroundStyle(t.textFaint)
      SimuPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func toggle(_ label: String, isOn: Binding<Bool>, hint: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Toggle(label, isOn: isOn)
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(t.body)
        .foregroundStyle(t.text)
      Text(hint)
        .font(t.caption)
        .foregroundStyle(t.textMuted)
    }
  }
}
