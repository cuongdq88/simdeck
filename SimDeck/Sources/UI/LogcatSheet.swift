import AppKit
import SwiftUI

/// Live `adb logcat`, with a text filter, level threshold, pause and copy.
struct LogcatSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  let device: Device

  @State private var query = ""
  @State private var minimumRank = -1
  @State private var paused = false
  @State private var snapshot: [String] = []

  private var source: [String] { paused ? snapshot : model.logcatLines }

  private var lines: [String] {
    source.filter { line in
      if !query.isEmpty, !line.localizedCaseInsensitiveContains(query) {
        return false
      }
      guard let level = Self.level(of: line) else { return true }
      return Self.rank(level) >= minimumRank
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      controls
      Rectangle().fill(t.border).frame(height: 1)
      log
      footer
    }
    .frame(width: 860, height: 580)
    .background(t.panel)
  }

  private var header: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Logcat — \(device.name)")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(t.text)
        Text("adb logcat -v time")
          .font(.custom("Menlo", size: 10))
          .foregroundStyle(t.textFaint)
      }
      Spacer()
      SimuIconButton(icon: "xmark", help: "Close", size: 14) {
        model.closeLogcat()
        dismiss()
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 16)
    .padding(.bottom, 10)
  }

  private var controls: some View {
    HStack(spacing: 8) {
      SimuTextField(text: $query, hint: "Filter", icon: "magnifyingglass")
        .frame(maxWidth: 320)

      Picker("", selection: $minimumRank) {
        Text("All").tag(-1)
        Text("V").tag(0)
        Text("D").tag(1)
        Text("I").tag(2)
        Text("W").tag(3)
        Text("E").tag(4)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 220)

      SimuIconButton(
        icon: paused ? "play.fill" : "pause.fill",
        help: paused ? "Resume" : "Pause",
        size: 13, active: paused
      ) {
        if paused {
          paused = false
          snapshot = []
        } else {
          snapshot = model.logcatLines
          paused = true
        }
      }

      SimuIconButton(icon: "trash", help: "Clear", size: 13) {
        model.clearLogcat()
        snapshot = []
      }

      SimuIconButton(icon: "doc.on.doc", help: "Copy all", size: 13) {
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.showNotice("Copied \(lines.count) lines")
      }

      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.bottom, 10)
  }

  private var log: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            Text(line.isEmpty ? " " : line)
              .font(.custom("Menlo", size: 10))
              .foregroundStyle(color(for: line))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .id(index)
          }
        }
        .padding(10)
      }
      .onChange(of: lines.count) { _, count in
        guard !paused, count > 0 else { return }
        proxy.scrollTo(count - 1, anchor: .bottom)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.opacity(0.18))
  }

  private var footer: some View {
    HStack {
      Text("\(lines.count) lines\(paused ? " · paused" : "")")
        .font(.custom("Menlo", size: 10))
        .foregroundStyle(t.textFaint)
      Spacer()
      SimuButton(label: "Done") {
        model.closeLogcat()
        dismiss()
      }
    }
    .padding(14)
    .overlay(alignment: .top) {
      Rectangle().fill(t.border).frame(height: 1)
    }
  }

  private func color(for line: String) -> Color {
    switch Self.level(of: line) {
    case "E": return t.danger
    case "W": return t.warning
    case "D": return t.textFaint
    default: return t.textMuted
    }
  }

  /// `08-14 12:34:56.789  1234  5678 I Tag: message`
  private static func level(of line: String) -> Character? {
    for part in line.split(separator: " ", omittingEmptySubsequences: true).prefix(6)
    where part.count == 1 {
      if let character = part.first, "VDIWE".contains(character) {
        return character
      }
    }
    return nil
  }

  private static func rank(_ level: Character) -> Int {
    switch level {
    case "V": return 0
    case "D": return 1
    case "I": return 2
    case "W": return 3
    case "E": return 4
    default: return 2
    }
  }
}
