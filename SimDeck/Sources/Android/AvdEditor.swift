import Foundation

struct AvdEditForm {
  var ramMb: Int
  var storage: String
  var cameraBack: String
  var orientation: String
  var keyboard: Bool
  /// `none`, `512M`, `1G` or `2G`.
  var sdCard: String
}

enum AvdEditError: LocalizedError {
  case missing(String)
  case writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .missing(let name): return "The AVD \(name) is no longer on disk."
    case .writeFailed(let message): return message
    }
  }
}

/// Edits a shut-down AVD's `config.ini` in place. Every other key, comment
/// and blank line is preserved byte for byte, and the file is written
/// atomically.
enum AvdEditor {
  static func update(name: String, form: AvdEditForm) throws {
    let directory = AvdStore.avdDirectory(for: name)
    let config = directory.appendingPathComponent("config.ini")
    guard let text = try? String(contentsOf: config, encoding: .utf8) else {
      throw AvdEditError.missing(name)
    }
    var updates: [String: String] = [
      "hw.ramSize": "\(form.ramMb)",
      "disk.dataPartition.size": form.storage,
      "hw.camera.back": form.cameraBack,
      "hw.initialOrientation": form.orientation == "landscape" ? "Landscape" : "Portrait",
      "hw.keyboard": form.keyboard ? "yes" : "no",
    ]
    if form.sdCard == "none" {
      updates["hw.sdCard"] = "no"
      updates["sdcard.size"] = "0"
    } else {
      updates["hw.sdCard"] = "yes"
      updates["sdcard.size"] = form.sdCard
    }
    let updated = apply(updates, to: text)
    do {
      try Data(updated.utf8).write(to: config, options: .atomic)
    } catch {
      throw AvdEditError.writeFailed(error.localizedDescription)
    }
  }

  /// Replaces matching `key=value` lines, keeping indentation and comments,
  /// and appends keys the file does not have yet.
  static func apply(_ updates: [String: String], to text: String) -> String {
    var remaining = updates
    var lines = text.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
        let equals = trimmed.firstIndex(of: "=")
      else { continue }
      let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
      guard let value = remaining[key] else { continue }
      let indent = String(line.prefix { $0 == " " || $0 == "\t" })
      lines[index] = "\(indent)\(key)=\(value)"
      remaining[key] = nil
    }
    if !remaining.isEmpty {
      let extra = remaining
        .map { "\($0.key)=\($0.value)" }
        .sorted()
      if lines.last == "" {
        lines.insert(contentsOf: extra, at: lines.count - 1)
      } else {
        lines.append(contentsOf: extra)
      }
    }
    return lines.joined(separator: "\n")
  }
}
