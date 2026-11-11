import Foundation

struct AvdCreateForm {
  var name: String
  var profile: HardwareProfile
  var image: SystemImage
  var ramMb: Int = 2048
  var storage: String = "8G"
  var cameraBack: String = "virtualscene"
  var cameraFront: String = "none"
  var orientation: String = "portrait"
  var keyboard: Bool = true
}

enum AvdCreateError: LocalizedError {
  case invalidName
  case nameExists(String)
  case imageMissing(String)
  case diskFull(required: Int64, available: Int64)
  case writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidName:
      return "Use letters, digits, spaces, dot, dash or underscore (max 64)."
    case .nameExists(let name):
      return "An AVD named \(name) already exists."
    case .imageMissing(let packageId):
      return "System image \(packageId) is not installed. Install it in SDK Manager."
    case .diskFull(let required, let available):
      let formatter = ByteCountFormatter()
      return "Not enough disk space: \(formatter.string(fromByteCount: required)) needed, "
        + "\(formatter.string(fromByteCount: available)) free."
    case .writeFailed(let message):
      return message
    }
  }
}

/// Writes the two AVD files the emulator reads. No `avdmanager`, no Java.
enum AvdCreator {
  /// The emulator crashes on an AVD whose `.ini` or directory name contains a
  /// space, so the typed name only lives in `avd.ini.displayname` and the files
  /// use underscores.
  static func avdID(for name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).joined(separator: "_")
  }

  static func isValidName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 64 else { return false }
    let id = avdID(for: trimmed)
    return id.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil
  }

  static func validate(name: String, existing: Set<String>) -> String? {
    guard isValidName(name) else {
      return "Use letters, digits, spaces, dot, dash or underscore (max 64)."
    }
    let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if existing.contains(avdID(for: display)) {
      return "An AVD named \(display) already exists."
    }
    return nil
  }

  static func create(_ form: AvdCreateForm, existing: Set<String>) throws -> AvdInfo {
    let display = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let avdID = avdID(for: display)
    guard validate(name: display, existing: existing) == nil else {
      if existing.contains(avdID) { throw AvdCreateError.nameExists(display) }
      throw AvdCreateError.invalidName
    }
    guard FileManager.default.fileExists(atPath: form.image.path.path) else {
      throw AvdCreateError.imageMissing(form.image.packageId)
    }

    let required: Int64 = 2 * 1024 * 1024 * 1024
    let home = URL(fileURLWithPath: ShellEnv.avdHome, isDirectory: true)
    let available = ShellEnv.freeDiskBytes(at: home)
    if available > 0 && available < required {
      throw AvdCreateError.diskFull(required: required, available: available)
    }

    let avdDir = home.appendingPathComponent("\(avdID).avd", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: avdDir, withIntermediateDirectories: true)
      let ini = """
        avd.ini.encoding=UTF-8
        path=\(avdDir.path)
        path.rel=avd/\(avdID).avd
        target=android-\(form.image.api)

        """
      try Data(ini.utf8).write(to: home.appendingPathComponent("\(avdID).ini"), options: .atomic)
      try Data(configINI(form: form, avdID: avdID, display: display).utf8)
        .write(to: avdDir.appendingPathComponent("config.ini"), options: .atomic)
    } catch {
      throw AvdCreateError.writeFailed(error.localizedDescription)
    }

    guard let info = AvdStore.load(name: avdID) else {
      throw AvdCreateError.writeFailed("The AVD was written but could not be read back.")
    }
    return info
  }

  private static func configINI(form: AvdCreateForm, avdID: String, display: String) -> String {
    let profile = form.profile
    let arch = form.image.abi.hasPrefix("arm64") ? "arm64" : "x86_64"
    let heap = max(128, min(1024, form.ramMb / 8))
    let cameraBack = form.cameraBack
    let cameraFront = form.cameraFront
    let orientation = form.orientation == "landscape" ? "Landscape" : "Portrait"
    return """
      AvdId=\(avdID)
      avd.ini.displayname=\(display)
      avd.ini.encoding=UTF-8
      abi.type=\(form.image.abi)
      hw.cpu.arch=\(arch)
      hw.cpu.ncore=4
      image.sysdir.1=\(form.image.sysdir)
      tag.id=\(form.image.tag)
      tag.display=\(form.image.tagLabel)
      hw.device.name=\(profile.id)
      hw.device.manufacturer=\(profile.manufacturer)
      hw.lcd.width=\(profile.width)
      hw.lcd.height=\(profile.height)
      hw.lcd.density=\(profile.density)
      hw.lcd.backlight=yes
      skin.dynamic=yes
      skin.name=\(profile.width)x\(profile.height)
      hw.initialOrientation=\(orientation)
      hw.ramSize=\(form.ramMb)
      vm.heapSize=\(heap)
      disk.dataPartition.size=\(form.storage)
      hw.keyboard=\(form.keyboard ? "yes" : "no")
      hw.mainKeys=no
      hw.camera.back=\(cameraBack)
      hw.camera.front=\(cameraFront)
      hw.gpu.enabled=yes
      hw.gpu.mode=auto
      hw.audioInput=yes
      hw.audioOutput=yes
      hw.sensors.proximity=yes
      hw.sensors.orientation=yes
      hw.sdCard=no
      showDeviceFrame=no
      fastboot.forceColdBoot=no
      fastboot.forceFastBoot=yes

      """
  }
}
