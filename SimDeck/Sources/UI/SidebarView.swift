import SwiftUI

private enum SidebarItem: Identifiable {
  case group(id: String, title: String, count: Int, addPlatform: Int?)
  case device(groupID: String, device: Device)

  var id: String {
    switch self {
    case .group(let id, _, _, _):
      return "group:\(id)"
    case .device(let groupID, let device):
      return "\(groupID):\(device.key)"
    }
  }
}

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
          ForEach(items) { item in
            switch item {
            case .group(let id, let title, let count, let addPlatform):
              groupHeader(id: id, title: title, count: count, addPlatform: addPlatform)
            case .device(_, let device):
              SidebarDeviceRow(
                device: device,
                onWipe: { wipeTarget = device },
                onDelete: { deleteTarget = device })
            }
          }
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
      SimuIconButton(icon: "wifi", help: "Connect a device over Wi-Fi", size: 15) {
        model.connectSheetShown = true
      }
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

  /// Flattened rows so a device that moves between groups gets a new
  /// identity: SwiftUI otherwise reuses the old row (and its buttons) for a
  /// moment.
  private var items: [SidebarItem] {
    var items: [SidebarItem] = []
    func add(
      id: String, title: String, devices: [Device],
      showWhenEmpty: Bool = false, addPlatform: Int? = nil
    ) {
      let visible = filter(devices)
      guard !visible.isEmpty || showWhenEmpty else { return }
      items.append(
        .group(id: id, title: title, count: visible.count, addPlatform: addPlatform))
      guard !collapsed.contains(id) else { return }
      items.append(contentsOf: visible.map { .device(groupID: id, device: $0) })
    }
    add(id: "running", title: "Running", devices: model.runningDevices, showWhenEmpty: true)
    add(
      id: "android-devices", title: "Android devices",
      devices: model.devices.filter { $0.os == .android && $0.kind == .physical })
    add(
      id: "android-emulators", title: "Android emulators",
      devices: model.devices.filter {
        $0.os == .android && $0.kind == .simulator && !$0.isRunning
      },
      showWhenEmpty: true, addPlatform: 0)
    add(
      id: "ios-simulators", title: "iOS simulators",
      devices: model.iosSimulators.filter { !$0.isRunning },
      showWhenEmpty: true, addPlatform: 1)
    return items
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
  @State private var editTarget: AvdInfo?

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
          if device.isRunning && (device.os == .ios || device.serial != nil) {
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
            if device.os == .android && device.kind == .simulator {
              SimuIconButton(icon: "pencil", help: "Edit device", size: 14) {
                beginEdit()
              }
            }
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
    .sheet(item: $editTarget) { avd in
      EditDeviceSheet(avd: avd)
        .environment(\.simu, t)
    }
    .contextMenu {
      if !device.isRunning {
        Button("Start") { Task { await model.start(device) } }
        if device.os == .android && device.kind == .simulator {
          Button("Start cold (no snapshot)") {
            Task { await model.start(device, coldBoot: true) }
          }
          Button("Edit…") { beginEdit() }
        }
      } else {
        Button("Stream") { Task { await model.openStream(device) } }
        if device.os == .android {
          Button("Logcat…") { model.openLogcat(device) }
        }
        Button("Restart") { Task { await model.restart(device) } }
        Button("Shut down") { Task { await model.stop(device) } }
      }
      if device.os == .android && device.kind == .simulator {
        Menu("Camera source") {
          cameraItem("AVD default", nil)
          cameraItem("Virtual scene", "virtualscene")
          cameraItem("Emulated", "emulated")
          cameraItem("None", "none")
          if !model.webcams.isEmpty {
            Divider()
            ForEach(model.webcams, id: \.self) { webcam in
              cameraItem(webcam, webcam)
            }
          }
        }
      }
      Divider()
      Button("Wipe data…") { onWipe() }
      Button("Delete…", role: .destructive) { onDelete() }
    }
  }

  private func beginEdit() {
    if let avd = AvdStore.load(name: device.rawID) {
      editTarget = avd
    }
  }

  private func cameraItem(_ title: String, _ value: String?) -> some View {
    Button {
      Task { await model.setCameraBack(device, source: value) }
    } label: {
      HStack {
        Text(title)
        if model.deviceSettings(device).cameraBack == value {
          Image(systemName: "checkmark")
        }
      }
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
