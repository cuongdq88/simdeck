import Foundation

struct GuardIssue: LocalizedError {
  let code: String
  let message: String
  var errorDescription: String? { message }
}

/// Refuses destructive AVD operations that would break another device.
enum DeletionGuard {
  static func checkAvd(name: String, running: Set<String>) -> GuardIssue? {
    let all = AvdStore.list()
    guard let target = all.first(where: { $0.name == name }) else {
      return GuardIssue(
        code: "not_found",
        message: "This AVD is no longer on disk; refresh the list.")
    }
    let targetPath = resolved(target.directory)
    let sharing = all
      .filter { $0.name != name && resolved($0.directory) == targetPath }
      .map(\.name)
      .sorted()
    if !sharing.isEmpty {
      return GuardIssue(
        code: "shared_dir",
        message: "Blocked: \(sharing.joined(separator: ", ")) and \(name) all point at "
          + "\(target.directory.path). Deleting one would destroy the others.")
    }
    if running.contains(name) {
      return GuardIssue(
        code: "device_running",
        message: "Stop \(name) before deleting or wiping it.")
    }
    return nil
  }

  static func checkImage(packageId: String, avds: [AvdInfo]? = nil) -> GuardIssue? {
    let users = (avds ?? AvdStore.list())
      .filter { $0.packageId == packageId }
      .map(\.name)
      .sorted()
    guard !users.isEmpty else { return nil }
    let names = users.joined(separator: ", ")
    let verb = users.count == 1 ? "boots" : "boot"
    return GuardIssue(
      code: "image_in_use",
      message: "Blocked: \(names) \(verb) from this image. Delete the AVD first.")
  }

  private static func resolved(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }
}
