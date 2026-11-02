import SwiftUI

/// Edits a shut-down AVD. The image identity (profile, API, tag, ABI) stays
/// locked, like Android Studio; everything else is written over the existing
/// `config.ini` without touching the other keys.
struct EditDeviceSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  let avd: AvdInfo

  @State private var ram: String
  @State private var storage: String
  @State private var camera: String
  @State private var orientation: String
  @State private var keyboard: Bool
  @State private var sdCard: String
  @State private var error: String?
  @State private var saving = false

  init(avd: AvdInfo) {
    self.avd = avd
    let config = AvdStore.parseINI(
      avd.directory.appendingPathComponent("config.ini"))
    _ram = State(initialValue: "\(avd.ramMb ?? Int(config["hw.ramSize"] ?? "") ?? 2048)")
    _storage = State(
      initialValue: avd.dataPartition ?? config["disk.dataPartition.size"] ?? "8G")
    _camera = State(initialValue: config["hw.camera.back"] ?? "virtualscene")
    _orientation = State(
      initialValue: (config["hw.initialOrientation"] ?? "Portrait").lowercased()
        == "landscape" ? "landscape" : "portrait")
    _keyboard = State(initialValue: (config["hw.keyboard"] ?? "yes") != "no")
    let size = config["sdcard.size"] ?? "0"
    _sdCard = State(
      initialValue: (config["hw.sdCard"] == "yes" && size != "0" && !size.isEmpty)
        ? size : "none")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Edit \(avd.name)")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(t.text)
        Text("Changes apply the next time this device boots.")
          .font(t.caption)
          .foregroundStyle(t.textMuted)
      }

      identity

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
        GridRow {
          label("RAM")
          HStack(spacing: 8) {
            SimuTextField(text: $ram, hint: "2048", monospace: true)
              .frame(width: 100)
            Text("MB").font(t.caption).foregroundStyle(t.textFaint)
            SimuTextField(text: $storage, hint: "8G", monospace: true)
              .frame(width: 80)
            Text("data").font(t.caption).foregroundStyle(t.textFaint)
          }
        }
        GridRow {
          label("Camera")
          Picker("", selection: $camera) {
            Text("Virtual scene").tag("virtualscene")
            Text("Emulated").tag("emulated")
            Text("None").tag("none")
          }
          .labelsHidden()
          .frame(width: 180)
        }
        GridRow {
          label("Orientation")
          Picker("", selection: $orientation) {
            Text("Portrait").tag("portrait")
            Text("Landscape").tag("landscape")
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 180)
        }
        GridRow {
          label("SD card")
          Picker("", selection: $sdCard) {
            Text("None").tag("none")
            Text("512 MB").tag("512M")
            Text("1 GB").tag("1G")
            Text("2 GB").tag("2G")
          }
          .labelsHidden()
          .frame(width: 180)
        }
        GridRow {
          label("Keyboard")
          Toggle("Hardware keyboard", isOn: $keyboard)
            .toggleStyle(.checkbox)
            .font(t.body)
        }
      }

      if let error {
        Text(error)
          .font(t.caption)
          .foregroundStyle(t.danger)
          .fixedSize(horizontal: false, vertical: true)
      }

      Rectangle().fill(t.border).frame(height: 1)

      HStack {
        Spacer()
        SimuButton(label: "Cancel") { dismiss() }
        SimuButton(
          label: saving ? "Saving…" : "Save",
          primary: true,
          action: saving ? nil : { Task { await save() } })
      }
    }
    .padding(20)
    .frame(width: 520)
    .background(t.panel)
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("IMAGE")
        .font(t.overline)
        .tracking(0.6)
        .foregroundStyle(t.textFaint)
      Text(avd.packageId ?? "Unknown image")
        .font(.custom("Menlo", size: 11))
        .foregroundStyle(t.text)
        .lineLimit(1)
        .truncationMode(.middle)
      if let tag = avd.tagId, let abi = avd.abi {
        Text("\(tag) · \(abi)")
          .font(.custom("Menlo", size: 10))
          .foregroundStyle(t.textFaint)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: SimuTokens.radius).fill(t.raised.opacity(0.5)))
    .overlay(
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .strokeBorder(t.border, lineWidth: 1))
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(t.body)
      .foregroundStyle(t.textMuted)
      .gridColumnAlignment(.trailing)
  }

  private func save() async {
    error = nil
    guard let ramMb = Int(ram), ramMb >= 512 else {
      error = "RAM must be at least 512 MB."
      return
    }
    saving = true
    defer { saving = false }
    await model.updateAvd(
      avd,
      form: AvdEditForm(
        ramMb: ramMb,
        storage: storage.isEmpty ? "8G" : storage,
        cameraBack: camera,
        orientation: orientation,
        keyboard: keyboard,
        sdCard: sdCard))
    if model.errorMessage != nil {
      error = model.errorMessage
      model.errorMessage = nil
    } else {
      dismiss()
    }
  }
}
