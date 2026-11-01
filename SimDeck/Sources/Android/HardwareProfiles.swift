import Foundation

/// A hardware profile the emulator can boot, written into `config.ini`
/// directly so creating an AVD needs no Java and no `avdmanager`.
struct HardwareProfile: Identifiable, Hashable {
  let id: String
  let name: String
  let width: Int
  let height: Int
  let density: Int
  let manufacturer: String
  let isTablet: Bool

  var screen: String { "\(width) × \(height)" }
  var label: String { "\(name) · \(screen) @ \(density) dpi" }
}

enum HardwareProfiles {
  static let all: [HardwareProfile] = [
    HardwareProfile(
      id: "pixel_9", name: "Pixel 9", width: 1080, height: 2424, density: 420,
      manufacturer: "Google", isTablet: false),
    HardwareProfile(
      id: "pixel_9_pro", name: "Pixel 9 Pro", width: 1280, height: 2856, density: 480,
      manufacturer: "Google", isTablet: false),
    HardwareProfile(
      id: "pixel_8", name: "Pixel 8", width: 1080, height: 2400, density: 420,
      manufacturer: "Google", isTablet: false),
    HardwareProfile(
      id: "pixel_7", name: "Pixel 7", width: 1080, height: 2400, density: 420,
      manufacturer: "Google", isTablet: false),
    HardwareProfile(
      id: "pixel_6", name: "Pixel 6", width: 1080, height: 2400, density: 420,
      manufacturer: "Google", isTablet: false),
    HardwareProfile(
      id: "medium_phone", name: "Medium Phone", width: 1080, height: 2400, density: 420,
      manufacturer: "Generic", isTablet: false),
    HardwareProfile(
      id: "small_phone", name: "Small Phone", width: 720, height: 1280, density: 320,
      manufacturer: "Generic", isTablet: false),
    HardwareProfile(
      id: "pixel_tablet", name: "Pixel Tablet", width: 2560, height: 1600, density: 320,
      manufacturer: "Google", isTablet: true),
    HardwareProfile(
      id: "medium_tablet", name: "Medium Tablet", width: 1600, height: 2560, density: 240,
      manufacturer: "Generic", isTablet: true),
    HardwareProfile(
      id: "tv_1080p", name: "TV 1080p", width: 1920, height: 1080, density: 320,
      manufacturer: "Generic", isTablet: false),
    HardwareProfile(
      id: "wear_round", name: "Wear OS Round", width: 454, height: 454, density: 320,
      manufacturer: "Generic", isTablet: false),
    HardwareProfile(
      id: "wear_small_round", name: "Wear OS Small Round", width: 384, height: 384, density: 320,
      manufacturer: "Generic", isTablet: false),
  ]

  static func profile(id: String) -> HardwareProfile? {
    all.first { $0.id == id }
  }
}
