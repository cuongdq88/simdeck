import SwiftUI

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  @State private var query = ""
  @State private var collapsed: Set<String> = []
  @State private var wipeTarget: Device?
  @State private var deleteTarget: Device?

  var body: some View {
    VStack(spacing: 0) {
      brand
      searchRow
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          group(
            id: "running", title: "Running", devices: filter(model.runningDevices),
            showWhenEmpty: true)
          group(
            id: "android-devices", title: "Android devices",
            devices: filter(model.devices.filter { $0.os == .android && $0.kind == .physical }))
          group(
            id: "android-emulators", title: "Android emulators",
            devices: filter(model.devices.filter {
              $0.os == .android && $0.kind == .simulator && !$0.isRunning
            }),
            showWhenEmpty: true, addPlatform: 0)
          group(
            id: "ios-simulators", title: "iOS simulators",
            devices: filter(model.iosSimulators.filter { !$0.isRunning }),
            showWhenEmpty: true, addPlatform: 1)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
      }
      .scrollIndicators(.never)
    }
    .background(t.sidebar)
    .overlay(alignment: .trailing) {
      Rectangle().fill(t.border).frame(width: 1).ignoresSafeArea()
    }
    .sheet(item: $wipeTarget) { device in
      WipeDialog(device: device) {
        Task { await model.wipe(device) }
      }
      .environment(\.simu, t)
    }
    .alert(
      "Delete “\(deleteTarget?.name ?? "")”?",
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } })
    ) {
      Button("Cancel", role: .cancel) { deleteTarget = nil }
      Button("Delete", role: .destructive) {
        if let device = deleteTarget {
          Task { await model.delete(device) }
        }
        deleteTarget = nil
      }
    } message: {
      Text(
        "Deletes the \(deleteTarget?.os == .android ? "AVD" : "simulator") and all of its data. "
          + "This cannot be undone.")
    }
  }

  // MARK: - Header

  private var brand: some View {
    HStack(spacing: 10) {
      SimuBrandLogo(size: 24)
      Text("SimDeck")
        .font(t.title)
        .foregroundStyle(t.text)
      Spacer()
    }
    .padding(.top, 40)
    .padding(.horizontal, 14)
    .padding(.bottom, 10)
  }

  private var searchRow: some View {
    HStack(spacing: 4) {
      SimuTextField(text: $query, hint: "Search devices", icon: "magnifyingglass")
      SimuIconButton(icon: "arrow.clockwise", help: "Refresh devices", size: 15) {
        Task { await model.refresh() }
      }
    }
    .padding(.leading, 12)
    .padding(.trailing, 8)
    .padding(.bottom, 4)
  }

  // MARK: - Groups

  private func filter(_ devices: [Device]) -> [Device] {
    let query = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return devices }
    return devices.filter { $0.name.lowercased().contains(query) }
  }

  @ViewBuilder
  private func group(
    id: String, title: String, devices: [Device],
    showWhenEmpty: Bool = false, addPlatform: Int? = nil
  ) -> some View {
    if !devices.isEmpty || showWhenEmpty {
      groupHeader(id: id, title: title, count: devices.count, addPlatform: addPlatform)
      if !collapsed.contains(id) {
        ForEach(devices) { device in
          SidebarDeviceRow(
            device: device,
            onWipe: { wipeTarget = device },
            onDelete: { deleteTarget = device })
        }
      }
    }
  }

  private func groupHeader(
    id: String, title: String, count: Int, addPlatform: Int?
  ) -> some View {
    let isCollapsed = collapsed.contains(id)
    return HStack(spacing: 4) {
      Button {
        if isCollapsed {
          collapsed.remove(id)
        } else {
          collapsed.insert(id)
        }
      } label: {
        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(t.textFaint)
          .frame(width: 14, height: 14)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Text(title.uppercased())
        .font(t.overline)
        .tracking(0.6)
        .foregroundStyle(t.textFaint)

      Spacer(minLength: 4)

      Text("\(count)")
        .font(.custom("Menlo", size: 11))
        .foregroundStyle(t.textMuted)

      if let addPlatform {
        SimuIconButton(
          icon: "plus",
          help: addPlatform == 0 ? "New Android emulator" : "New iOS simulator",
          size: 13
        ) {
          model.createPlatform = addPlatform
          model.createSheetShown = true
        }
      }
    }
    .padding(.top, 12)
    .padding(.bottom, 4)
    .padding(.leading, 4)
  }
}

struct SidebarDeviceRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.simu) private var t

  let device: Device
  let onWipe: () -> Void
  let onDelete: () -> Void

  @State private var hovered = false

  private var streaming: Bool { model.sessions[device.key] != nil }
  private var busy: Bool { model.isBusy(device) }

  var body: some View {
    HStack(spacing: 10) {
      DeviceGlyph(device: device, busy: busy)

      VStack(alignment: .leading, spacing: 4) {
        Text(device.name)
          .font(t.label)
          .foregroundStyle(t.text)
          .lineLimit(1)
          .truncationMode(.tail)
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(t.monoSmall)
            .foregroundStyle(t.textMuted)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 2)

      if busy {
        SimuSpinner().padding(6)
      } else {
        HStack(spacing: 0) {
          if !device.isPhysical && !device.isRunning {
            SimuIconButton(icon: "play.fill", help: "Start", size: 15) {
              Task { await model.start(device) }
            }
          }
          if device.isRunning {
            SimuIconButton(
              icon: "play.rectangle",
              help: streaming ? "Streaming" : "Stream",
              size: 15, active: streaming
            ) {
              Task { await model.openStream(device) }
            }
          }
          if !device.isPhysical && device.isRunning {
            SimuIconButton(icon: "power", help: "Shut down", size: 15) {
              Task { await model.stop(device) }
            }
          }
          if !device.isPhysical && !device.isRunning {
            SimuIconButton(icon: "eraser", help: "Wipe data", size: 14, action: onWipe)
            SimuIconButton(icon: "trash", help: "Delete device", size: 14, action: onDelete)
          }
        }
      }
    }
    .padding(.leading, 6)
    .padding(.trailing, 4)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .fill(background))
    .onHover { hovered = $0 }
    .contextMenu {
      if !device.isRunning {
        Button("Start") { Task { await model.start(device) } }
      } else {
        Button("Stream") { Task { await model.openStream(device) } }
        Button("Shut down") { Task { await model.stop(device) } }
      }
      Divider()
      Button("Wipe data…") { onWipe() }
      Button("Delete…", role: .destructive) { onDelete() }
    }
  }

  private var subtitle: String {
    [
      device.platform.contains(where: \.isNumber) ? device.platform : nil,
      streaming ? "streaming" : nil,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }

  private var background: Color {
    if streaming {
      return t.accent.opacity(hovered ? 0.14 : 0.08)
    }
    return hovered ? t.hover : .clear
  }
}

struct DeviceGlyph: View {
  @Environment(\.simu) private var t

  let device: Device
  var busy = false

  var body: some View {
    let tint = device.os == .android ? t.android : t.apple
    ZStack(alignment: .bottomTrailing) {
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .fill(tint.opacity(0.13))
        .frame(width: 32, height: 32)
        .overlay {
          Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(tint)
        }
      SimuStatusDot(
        color: busy ? t.warning : (device.isRunning ? t.success : t.textFaint),
        size: 10, ring: t.sidebar)
        .offset(x: 3, y: 3)
    }
    .frame(width: 32, height: 32)
  }

  private var symbol: String {
    let name = device.name.lowercased()
    if name.contains("tv") || name.contains("television") { return "tv" }
    if name.contains("watch") || name.contains("wear") { return "applewatch" }
    if name.contains("ipad") || name.contains("tablet") { return "ipad" }
    return "iphone"
  }
}
