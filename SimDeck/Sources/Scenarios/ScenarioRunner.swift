import Foundation

/// Runs one list of steps on several devices at once, each on its own, and
/// reports where each device stands. Steps arrive as JSON step objects (see
/// the `run_scenario` tool); steps that name a label are Android only.
@MainActor
final class ScenarioRunner {
  /// Label lookups wait this long by default: one `uiautomator dump` costs a
  /// couple of seconds, so 5 s often allowed just one look at a loading screen.
  private static let defaultTimeoutMs = 10_000

  /// Runs still going, and whether each was asked to stop.
  private var running: [Int: Bool] = [:]
  private var nextRunID = 1

  /// Runs `steps` on `devices` and returns `{run_id, prep_ms, devices}`.
  /// Every device is readied first, then all start from the same clock.
  func run(
    steps: [[String: Any]], devices: [Device], model: AppModel
  ) async -> [String: Any] {
    let runID = nextRunID
    nextRunID += 1
    running[runID] = false
    defer { running[runID] = nil }

    let prepClock = Date()
    var readying: [Task<Void, Never>] = []
    for device in devices where model.session(for: device) == nil {
      readying.append(Task { @MainActor in await model.openStream(device) })
    }
    for task in readying { await task.value }
    let prepMs = ms(since: prepClock)

    let start = Date()
    var tasks: [Task<(Int, [String: Any]), Never>] = []
    for (index, device) in devices.enumerated() {
      tasks.append(
        Task { @MainActor in
          (index, await self.run(device, steps: steps, model: model, runID: runID, clock: start))
        })
    }
    var results: [(Int, [String: Any])] = []
    for task in tasks { results.append(await task.value) }
    return [
      "run_id": runID,
      "prep_ms": prepMs,
      "devices": results.sorted { $0.0 < $1.0 }.map(\.1),
    ]
  }

  /// Marks a run stopped, or every run when [runID] is nil; each device stops
  /// at its next step or wait. Returns the ids that were running.
  @discardableResult
  func stop(_ runID: Int?) -> [Int] {
    if let runID {
      guard running[runID] != nil else { return [] }
      running[runID] = true
      return [runID]
    }
    let ids = running.keys.sorted()
    for id in ids { running[id] = true }
    return ids
  }

  // MARK: - One device

  private func run(
    _ device: Device, steps: [[String: Any]], model: AppModel, runID: Int,
    clock: Date
  ) async -> [String: Any] {
    guard let session = model.session(for: device) else {
      return [
        "device": device.name, "ok": false, "failed_step": 0,
        "error": model.sessionErrors[device.key] ?? "The stream did not start.",
      ]
    }
    let start = ms(since: clock)
    var stepsMs: [Int] = []
    do {
      for step in steps {
        let at = Date()
        try checkStop(runID)
        if try await conditionHolds(step, device: device) {
          for _ in 0..<max(step["repeat"] as? Int ?? 1, 1) {
            try checkStop(runID)
            try await run(step, device: device, session: session, model: model, runID: runID)
          }
        }
        stepsMs.append(ms(since: at))
      }
      return [
        "device": device.name, "ok": true, "start_ms": start,
        "end_ms": ms(since: clock), "steps_ms": stepsMs,
      ]
    } catch {
      return [
        "device": device.name, "ok": false, "failed_step": stepsMs.count,
        "error": error.localizedDescription,
      ]
    }
  }

  private func run(
    _ step: [String: Any], device: Device, session: DeviceSession,
    model: AppModel, runID: Int
  ) async throws {
    switch step["action"] as? String ?? "" {
    case "tap":
      try await tap(step, device: device, session: session, runID: runID)
    case "swipe":
      try await swipe(step, device: device, session: session, runID: runID)
    case "press":
      let raw = step["button"] as? String ?? ""
      guard let button = DeviceButton(rawValue: raw) else {
        throw ScenarioError.message("Unknown button \(raw).")
      }
      session.press(button)
    case "launch":
      guard let app = Self.appID(device, step) else {
        throw ScenarioError.message(
          "launch has no app id for \(device.os == .android ? "Android" : "iOS").")
      }
      try await model.launchApp(
        device, app: app, clearState: step["clear_state"] as? Bool ?? false)
    case "type":
      session.typeText(step["text"] as? String ?? "")
    case "assert_visible":
      _ = try await locate(
        try Self.label(step), device: device, index: 0,
        timeoutMs: step["timeout_ms"] as? Int ?? Self.defaultTimeoutMs, runID: runID)
    case "assert_not_visible":
      try await waitGone(
        try Self.label(step), device: device,
        timeoutMs: step["timeout_ms"] as? Int ?? Self.defaultTimeoutMs, runID: runID)
    case "wait":
      try await pause(Double(step["ms"] as? Int ?? 0) / 1000, runID: runID)
    default:
      throw ScenarioError.message("Unknown action \(step["action"] ?? "").")
    }
  }

  // MARK: - Steps

  private func tap(
    _ step: [String: Any], device: Device, session: DeviceSession, runID: Int
  ) async throws {
    let point: (x: Double, y: Double)
    if let label = step["label"] as? String, !label.isEmpty {
      let element = try await locate(
        label, device: device, index: step["index"] as? Int ?? 0,
        timeoutMs: step["timeout_ms"] as? Int ?? Self.defaultTimeoutMs, runID: runID)
      point = element.center
    } else {
      point = (
        try Self.coord(step, "x"),
        try Self.coord(step, "y")
      )
    }
    session.touch(.down, x: point.x, y: point.y)
    // A stop check here could leave the finger down; stop lands after the tap.
    try? await Task.sleep(nanoseconds: 60_000_000)
    session.touch(.up, x: point.x, y: point.y)
  }

  private func swipe(
    _ step: [String: Any], device: Device, session: DeviceSession, runID: Int
  ) async throws {
    let x1: Double, y1: Double, x2: Double, y2: Double
    if let label = step["label"] as? String, !label.isEmpty {
      let from = try await locate(
        label, device: device, index: step["index"] as? Int ?? 0,
        timeoutMs: step["timeout_ms"] as? Int ?? Self.defaultTimeoutMs, runID: runID)
      x1 = from.center.x
      y1 = from.center.y
      x2 = min(max(x1 + (Self.number(step["dx"]) ?? 0), 0), 1)
      y2 = min(max(y1 + (Self.number(step["dy"]) ?? 0), 0), 1)
    } else {
      x1 = try Self.coord(step, "x1")
      y1 = try Self.coord(step, "y1")
      x2 = try Self.coord(step, "x2")
      y2 = try Self.coord(step, "y2")
    }
    let until = step["until"] as? String
    let maxSwipes = until == nil ? 1 : max(step["max"] as? Int ?? 20, 1)
    for _ in 0..<maxSwipes {
      if let until, try await contains(until, device: device) { return }
      try await drag(
        session, x1: x1, y1: y1, x2: x2, y2: y2,
        durationMs: step["duration_ms"] as? Int ?? 300)
      // Let the scroll settle (a wheel snaps to an item) before looking again.
      if until != nil { try await pause(0.35, runID: runID) }
    }
    if let until, try !(await contains(until, device: device)) {
      throw ScenarioError.message(
        "No element \"\(until)\" on \(device.name) after \(maxSwipes) swipes.")
    }
  }

  private func drag(
    _ session: DeviceSession, x1: Double, y1: Double, x2: Double, y2: Double,
    durationMs: Int
  ) async throws {
    let duration = min(max(durationMs, 50), 3000)
    session.touch(.down, x: x1, y: y1)
    let clock = Date()
    while true {
      try await Task.sleep(nanoseconds: 16_000_000)
      let elapsed = ms(since: clock)
      if elapsed >= duration { break }
      let t = Double(elapsed) / Double(duration)
      session.touch(.move, x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)
    }
    session.touch(.up, x: x2, y: y2)
  }

  private func waitGone(
    _ label: String, device: Device, timeoutMs: Int, runID: Int
  ) async throws {
    let timeout = min(max(timeoutMs, 0), 60_000)
    let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
    while try await contains(label, device: device) {
      if Date() >= deadline {
        throw ScenarioError.message(
          "\"\(label)\" still visible on \(device.name) after \(timeout) ms.")
      }
      try await pause(0.3, runID: runID)
    }
  }

  /// Whether the step's if_visible / if_not_visible holds; checked once.
  private func conditionHolds(
    _ step: [String: Any], device: Device
  ) async throws -> Bool {
    let shown = step["if_visible"] as? String
    let hidden = step["if_not_visible"] as? String
    guard shown != nil || hidden != nil else { return true }
    let all = try await elements(device)
    if let shown, UiAutomation.locate(label: shown, index: 0, in: all) == nil {
      return false
    }
    if let hidden, UiAutomation.locate(label: hidden, index: 0, in: all) != nil {
      return false
    }
    return true
  }

  // MARK: - Elements

  private func elements(_ device: Device) async throws -> [UiElement] {
    guard device.os == .android, let serial = device.serial else {
      throw ScenarioError.message(
        "Label steps support Android devices only; pass x and y coordinates on "
          + "\(device.name).")
    }
    return await UiAutomation.elements(serial: serial)
  }

  private func contains(_ label: String, device: Device) async throws -> Bool {
    UiAutomation.locate(label: label, index: 0, in: try await elements(device)) != nil
  }

  /// The element [label] names, polling until it shows up.
  private func locate(
    _ label: String, device: Device, index: Int, timeoutMs: Int, runID: Int
  ) async throws -> UiElement {
    let timeout = min(max(timeoutMs, 0), 60_000)
    let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
    while true {
      if let element = UiAutomation.locate(
        label: label, index: index, in: try await elements(device))
      {
        return element
      }
      if Date() >= deadline {
        throw ScenarioError.message(
          "No element \"\(label)\" on \(device.name) after \(timeout) ms.")
      }
      try await pause(0.3, runID: runID)
    }
  }

  // MARK: - Stop

  private func checkStop(_ runID: Int) throws {
    if running[runID] == true { throw ScenarioError.message("Stopped") }
  }

  /// Sleeps, checking for a stop request every 100 ms.
  private func pause(_ seconds: Double, runID: Int) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while true {
      try checkStop(runID)
      let left = deadline.timeIntervalSinceNow
      if left <= 0 { return }
      try await Task.sleep(nanoseconds: UInt64(min(left, 0.1) * 1_000_000_000))
    }
  }

  // MARK: - Values

  private func ms(since start: Date) -> Int {
    Int(Date().timeIntervalSince(start) * 1000)
  }

  private static func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
  }

  private static func coord(_ step: [String: Any], _ key: String) throws -> Double {
    guard let value = number(step[key]), value >= 0, value <= 1 else {
      throw ScenarioError.message("\(key) must be a number 0..1.")
    }
    return value
  }

  private static func label(_ step: [String: Any]) throws -> String {
    guard let value = step["label"] as? String, !value.isEmpty else {
      throw ScenarioError.message("\(step["action"] ?? "step") needs a label.")
    }
    return value
  }

  private static func appID(_ device: Device, _ step: [String: Any]) -> String? {
    let value = step[device.os == .android ? "android" : "ios"] ?? step["app"]
    guard let value = value as? String, !value.isEmpty else { return nil }
    return value
  }

  // MARK: - Validation

  /// Checks every step up front so a typo fails before any device moves.
  static func validate(_ steps: [[String: Any]]) throws {
    guard !steps.isEmpty else {
      throw ScenarioError.message("A scenario needs at least one step.")
    }
    for step in steps {
      for key in ["if_visible", "if_not_visible"] {
        if let value = step[key] {
          guard let text = value as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty
          else { throw ScenarioError.message("\(key) must be a label.") }
        }
      }
      if let shown = step["if_visible"] as? String,
        shown == step["if_not_visible"] as? String
      {
        throw ScenarioError.message(
          "if_visible and if_not_visible name the same label; the step would never run.")
      }
      if let count = step["repeat"], !(count is Int) || (count as? Int ?? 0) < 1 {
        throw ScenarioError.message("repeat must be an integer >= 1.")
      }
      guard let action = step["action"] as? String else {
        throw ScenarioError.message("Every step needs an action.")
      }
      switch action {
      case "tap":
        if step["label"] != nil { _ = try label(step) } else {
          _ = try coord(step, "x")
          _ = try coord(step, "y")
        }
      case "swipe":
        if step["label"] != nil {
          _ = try label(step)
          guard number(step["dx"]) != nil || number(step["dy"]) != nil else {
            throw ScenarioError.message("swipe from a label needs dx or dy.")
          }
        } else {
          for key in ["x1", "y1", "x2", "y2"] { _ = try coord(step, key) }
        }
        if let until = step["until"], !(until is String) {
          throw ScenarioError.message("until must be a label.")
        }
        if let max = step["max"], !(max is Int) || (max as? Int ?? 0) < 1 {
          throw ScenarioError.message("max must be an integer >= 1.")
        }
      case "press":
        let raw = step["button"] as? String ?? ""
        guard DeviceButton(rawValue: raw) != nil else {
          throw ScenarioError.message("Unknown button \(raw).")
        }
      case "wait":
        guard step["ms"] is Int else {
          throw ScenarioError.message("wait needs integer ms.")
        }
      case "launch":
        guard step["app"] is String || step["android"] is String || step["ios"] is String
        else { throw ScenarioError.message("launch needs app (or android / ios).") }
        if let clear = step["clear_state"], !(clear is Bool) {
          throw ScenarioError.message("clear_state must be true or false.")
        }
      case "type":
        guard step["text"] is String else {
          throw ScenarioError.message("type needs text.")
        }
      case "assert_visible", "assert_not_visible":
        _ = try label(step)
      default:
        throw ScenarioError.message(
          "Unknown action \(action); use tap, swipe, press, wait, launch, type, "
            + "assert_visible or assert_not_visible.")
      }
    }
  }
}

enum ScenarioError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}
