import AppKit
import SwiftUI

struct TopBar: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  let sidebarOpen: Bool
  let onToggleSidebar: () -> Void

  @State private var environmentShown = false
  @State private var mcpShown = false
  @State private var noticesShown = false
  @State private var recordingsShown = false

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
        ForEach(StreamLayout.allCases) { layout in
          SimuIconButton(
            icon: layout.symbol,
            help: layout.label,
            active: model.layout == layout,
            action: { model.setLayout(layout) })
        }
        SimuToolbarDivider()
        SimuIconButton(
          icon: "externaldrive",
          help: "SDK Manager",
          action: { model.sdkSheetShown = true })
        SimuIconButton(
          icon: "stethoscope",
          help: "Environment check",
          action: { environmentShown.toggle() })
          .popover(isPresented: $environmentShown, arrowEdge: .bottom) {
            environment
          }
        SimuIconButton(
          icon: "powerplug",
          help: model.mcpRunning ? "MCP is running" : "Connect an agent (MCP)",
          color: model.mcpRunning ? nil : t.danger,
          action: { mcpShown.toggle() })
          .popover(isPresented: $mcpShown, arrowEdge: .bottom) {
            mcp
          }
        SimuToolbarDivider()
        gridRecordingControl
        SimuIconButton(
          icon: "film",
          help: "Recordings",
          active: recordingsShown,
          action: { recordingsShown.toggle() })
          .sheet(isPresented: $recordingsShown) {
            RecordingsList()
              .environment(\.simu, t)
          }
        SimuToolbarDivider()
        SimuIconButton(
          icon: "bell",
          help: "Recent notifications",
          active: noticesShown,
          action: { noticesShown.toggle() })
          .overlay(alignment: .topTrailing) {
            if model.unreadNotices > 0 {
              Circle()
                .fill(t.danger)
                .frame(width: 6, height: 6)
                .padding(.top, 3)
                .padding(.trailing, 3)
            }
          }
          .popover(isPresented: $noticesShown, arrowEdge: .bottom) {
            notifications
          }
        SimuIconButton(
          icon: "gearshape",
          help: "Settings",
          action: { model.settingsSheetShown = true })
      }
    }
    .padding(.leading, sidebarOpen ? 10 : 78)
    .padding(.trailing, 16)
    .frame(height: 52)
    .background(t.page)
  }

  private var gridRecordingControl: some View {
    Group {
      if let start = model.gridRecordingStart {
        HStack(spacing: 6) {
          Circle().fill(t.danger).frame(width: 6, height: 6)
          Text(elapsed(since: start))
            .font(t.monoSmall)
            .foregroundStyle(t.danger)
          SimuIconButton(icon: "stop.fill", help: "Stop grid recording", color: t.danger) {
            Task { await model.toggleGridRecording() }
          }
        }
      } else {
        Menu {
          ForEach(GridRecordQuality.allCases) { quality in
            Button("Record — \(quality.label)") {
              Task { await model.toggleGridRecording(quality: quality) }
            }
          }
        } label: {
          Image(systemName: "record.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(t.textMuted)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Record the grid")
      }
    }
  }

  private func elapsed(since start: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(start)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
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

  private var mcp: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Circle()
          .fill(model.mcpRunning ? Color.green : Color.orange)
          .frame(width: 7, height: 7)
        Text("MCP server")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        Text(model.mcpRunning ? "running" : "stopped")
          .font(.custom("Menlo", size: 10))
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Text(model.mcpURL)
          .font(.custom("Menlo", size: 11))
          .textSelection(.enabled)
        Spacer()
        Button("Copy") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(model.mcpURL, forType: .string)
        }
        .controlSize(.small)
      }
      if let error = model.mcpError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.orange)
      }
      Text("Add this to your agent's MCP config:")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(
        """
        { "mcp": { "simdeck": {
            "type": "remote",
            "url": "\(model.mcpURL)" } } }
        """
      )
      .font(.custom("Menlo", size: 10))
      .textSelection(.enabled)
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.black.opacity(0.18))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .padding(14)
    .frame(width: 400)
  }

  private var notifications: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text("Notifications")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        if !model.notices.isEmpty {
          Button("Clear") { model.clearNotices() }
            .controlSize(.small)
        }
      }

      if model.notices.isEmpty {
        Text("Nothing yet. Starts, streams and captures show up here.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(model.notices) { entry in
              Button {
                model.replayNotice(entry)
              } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                  Text(entry.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                  Spacer(minLength: 6)
                  Text(entry.date, format: .dateTime.hour().minute())
                    .font(.custom("Menlo", size: 10))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 260)
      }
    }
    .padding(14)
    .frame(width: 380)
    .onAppear { model.markNoticesRead() }
    .onChange(of: model.notices.count) { _, _ in model.markNoticesRead() }
  }
}

/// Saved screen recordings from the capture folder.
struct RecordingsList: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  @State private var files: [URL] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Recordings")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(t.text)
          Text(model.recordingDirectory.path)
            .font(t.monoSmall)
            .foregroundStyle(t.textMuted)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 12)
        SimuButton(label: "Open folder", icon: "folder") {
          NSWorkspace.shared.open(model.recordingDirectory)
        }
        SimuIconButton(icon: "xmark", help: "Close", size: 14) { dismiss() }
      }
      .padding(20)
      Divider()
      if files.isEmpty {
        VStack(spacing: 8) {
          Text("No recordings yet")
            .font(t.body)
            .foregroundStyle(t.text)
          Text("Record a device from its tile, or the grid from the top bar.")
            .font(t.caption)
            .foregroundStyle(t.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(files, id: \.self) { file in
              row(file)
              Divider()
            }
          }
        }
        .padding(.horizontal, 16)
      }
    }
    .frame(width: 560, height: 420)
    .background(t.panel)
    .onAppear { files = model.savedRecordings() }
  }

  private func row(_ url: URL) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(url.deletingPathExtension().lastPathComponent)
          .font(.system(size: 12))
          .foregroundStyle(t.text)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(meta(url))
          .font(t.monoSmall)
          .foregroundStyle(t.textMuted)
      }
      Spacer(minLength: 6)
      SimuIconButton(icon: "play.rectangle", help: "Open", size: 13) {
        NSWorkspace.shared.open(url)
      }
      SimuIconButton(icon: "folder", help: "Reveal in Finder", size: 13) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      }
      SimuIconButton(icon: "trash", help: "Move to Trash", size: 13) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        files = model.savedRecordings()
      }
    }
    .padding(.vertical, 8)
  }

  private func meta(_ url: URL) -> String {
    let values = try? url.resourceValues(
      forKeys: [.fileSizeKey, .contentModificationDateKey])
    let size = values?.fileSize.map {
      ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
    } ?? ""
    let date = values?.contentModificationDate?.formatted(
      date: .abbreviated, time: .shortened) ?? ""
    return [date, size].filter { !$0.isEmpty }.joined(separator: " · ")
  }
}
