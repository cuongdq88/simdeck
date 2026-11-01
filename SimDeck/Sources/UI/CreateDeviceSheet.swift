import SwiftUI

struct CreateDeviceSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  @State private var platform = 0
  @State private var name = ""
  @State private var profileID = ""
  @State private var imageID = ""
  @State private var ram = "2048"
  @State private var storage = "8G"
  @State private var camera = "virtualscene"
  @State private var orientation = "portrait"
  @State private var hardwareKeyboard = true

  @State private var deviceTypes: [SimulatorDeviceType] = []
  @State private var runtimes: [SimulatorRuntime] = []
  @State private var deviceTypeID = ""
  @State private var runtimeID = ""

  @State private var error: String?
  @State private var creating = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("New device")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(t.text)
        Text("Create an Android emulator or an iOS simulator.")
          .font(t.caption)
          .foregroundStyle(t.textMuted)
      }

      Picker("Platform", selection: $platform) {
        Text("Android").tag(0)
        Text("iOS").tag(1)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if platform == 0 { androidForm } else { iosForm }

      if let error {
        Text(error)
          .font(t.caption)
          .foregroundStyle(t.danger)
          .fixedSize(horizontal: false, vertical: true)
      }

      Rectangle().fill(t.border).frame(height: 1)

      HStack(spacing: 8) {
        if platform == 0 {
          Text(model.androidHome)
            .font(.custom("Menlo", size: 10))
            .foregroundStyle(t.textFaint)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
        SimuButton(label: "Cancel") { dismiss() }
        SimuButton(
          label: creating ? "Creating…" : "Create",
          primary: true,
          action: canCreate && !creating ? { Task { await create() } } : nil)
      }
    }
    .padding(20)
    .frame(width: 560)
    .background(t.panel)
    .onAppear { platform = model.createPlatform }
    .task { await load() }
  }

  // MARK: - Android

  private var androidForm: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
      GridRow {
        label("Name")
        SimuTextField(text: $name, hint: "Pixel_9_API_36", monospace: true)
      }
      GridRow {
        label("Profile")
        Picker("", selection: $profileID) {
          ForEach(HardwareProfiles.all) { profile in
            Text(profile.label).tag(profile.id)
          }
        }
        .labelsHidden()
        .onChange(of: profileID) { _, _ in suggestNameIfNeeded() }
      }
      GridRow {
        label("Image")
        if model.images.isEmpty {
          Text("No system images installed")
            .font(t.caption)
            .foregroundStyle(t.warning)
        } else {
          Picker("", selection: $imageID) {
            ForEach(model.images) { image in
              Text(image.label).tag(image.packageId)
            }
          }
          .labelsHidden()
          .onChange(of: imageID) { _, _ in suggestNameIfNeeded() }
        }
      }
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
        HStack(spacing: 8) {
          Picker("", selection: $camera) {
            Text("Virtual scene").tag("virtualscene")
            Text("Emulated").tag("emulated")
            Text("None").tag("none")
          }
          .labelsHidden()
          .frame(width: 160)
          Picker("", selection: $orientation) {
            Text("Portrait").tag("portrait")
            Text("Landscape").tag("landscape")
          }
          .labelsHidden()
          .frame(width: 140)
        }
      }
      GridRow {
        label("Keyboard")
        Toggle("Hardware keyboard", isOn: $hardwareKeyboard)
          .toggleStyle(.checkbox)
          .font(t.body)
      }
    }
  }

  // MARK: - iOS

  private var iosForm: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
      GridRow {
        label("Name")
        SimuTextField(text: $name, hint: "iPhone 17")
      }
      GridRow {
        label("Device")
        if deviceTypes.isEmpty {
          Text("No simulator device types")
            .font(t.caption)
            .foregroundStyle(t.warning)
        } else {
          Picker("", selection: $deviceTypeID) {
            ForEach(deviceTypes) { type in
              Text(type.name).tag(type.id)
            }
          }
          .labelsHidden()
        }
      }
      GridRow {
        label("Runtime")
        if runtimes.isEmpty {
          Text("No installed iOS runtimes")
            .font(t.caption)
            .foregroundStyle(t.warning)
        } else {
          Picker("", selection: $runtimeID) {
            ForEach(runtimes) { runtime in
              Text(runtime.name).tag(runtime.id)
            }
          }
          .labelsHidden()
        }
      }
    }
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(t.body)
      .foregroundStyle(t.textMuted)
      .gridColumnAlignment(.trailing)
  }

  // MARK: - Data

  private var selectedProfile: HardwareProfile? {
    HardwareProfiles.profile(id: profileID) ?? HardwareProfiles.all.first
  }

  private var selectedImage: SystemImage? {
    model.images.first { $0.packageId == imageID } ?? model.images.first
  }

  private var nameValid: Bool {
    name.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil
  }

  private var canCreate: Bool {
    guard nameValid else { return false }
    if platform == 0 {
      return selectedImage != nil && selectedProfile != nil
    }
    return !deviceTypeID.isEmpty && !runtimeID.isEmpty
  }

  private func load() async {
    if profileID.isEmpty { profileID = HardwareProfiles.all.first?.id ?? "" }
    if imageID.isEmpty { imageID = model.images.first?.packageId ?? "" }
    if name.isEmpty { suggestNameIfNeeded() }

    async let types = SimctlService.deviceTypes()
    async let versions = SimctlService.runtimes()
    deviceTypes = await types
    runtimes = await versions
    if deviceTypeID.isEmpty { deviceTypeID = deviceTypes.first?.id ?? "" }
    if runtimeID.isEmpty { runtimeID = runtimes.first?.id ?? "" }
    if platform == 1, name.isEmpty { name = deviceTypes.first?.name ?? "iPhone" }
  }

  private func suggestNameIfNeeded() {
    guard platform == 0, let profile = selectedProfile, let image = selectedImage else { return }
    if name.isEmpty || name.hasPrefix("pixel") || name.hasPrefix("medium")
      || name.hasPrefix("small") || name.hasPrefix("wear") || name.hasPrefix("tv")
    {
      name = "\(profile.id)_API_\(image.api)"
    }
  }

  private func create() async {
    error = nil
    creating = true
    defer { creating = false }
    do {
      if platform == 0 {
        guard let profile = selectedProfile, let image = selectedImage else {
          throw AvdCreateError.imageMissing(imageID)
        }
        let form = AvdCreateForm(
          name: name,
          profile: profile,
          image: image,
          ramMb: Int(ram) ?? 2048,
          storage: storage.isEmpty ? "8G" : storage,
          cameraBack: camera,
          cameraFront: "none",
          orientation: orientation,
          keyboard: hardwareKeyboard)
        try await model.createAndroid(form)
      } else {
        try await model.createSimulator(
          name: name, deviceTypeID: deviceTypeID, runtimeID: runtimeID)
      }
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
