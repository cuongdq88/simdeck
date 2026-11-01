import SwiftUI

/// Wiping asks for the device name, like SimUtil: a stray click must not
/// erase a phone.
struct WipeDialog: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  let device: Device
  let onConfirm: () -> Void

  @State private var typed = ""

  private var matches: Bool {
    typed.trimmingCharacters(in: .whitespaces) == device.name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Wipe “\(device.name)”?")
        .font(t.title)
        .foregroundStyle(t.text)
      Text(
        "Erases apps, settings and snapshots on \(device.name). "
          + "Type the device name to confirm.")
        .font(t.body)
        .foregroundStyle(t.textMuted)
        .fixedSize(horizontal: false, vertical: true)

      SimuTextField(text: $typed, hint: device.name, monospace: true)

      HStack(spacing: 8) {
        Spacer()
        SimuButton(label: "Cancel") { dismiss() }
        SimuButton(
          label: "Wipe", primary: true,
          action: matches
            ? {
              onConfirm()
              dismiss()
            }
            : nil)
      }
    }
    .padding(20)
    .frame(width: 420)
    .background(t.panel)
  }
}
