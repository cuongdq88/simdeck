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
