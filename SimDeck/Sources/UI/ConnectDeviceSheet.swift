import SwiftUI

/// Pair and connect an Android device over Wi-Fi, using adb's mDNS browser
/// or an address typed in by hand.
struct ConnectDeviceSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  @State private var host = ""
  @State private var code = ""
  @State private var status: String?
  @State private var busy = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Connect over Wi-Fi")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(t.text)
          Text("Turn on Wireless debugging in the device's Developer options.")
            .font(t.caption)
            .foregroundStyle(t.textMuted)
        }
        Spacer()
        SimuIconButton(icon: "arrow.clockwise", help: "Look again", size: 14) {
          Task { await model.refreshMdns() }
        }
        SimuIconButton(icon: "xmark", help: "Close", size: 14) { dismiss() }
      }

      discovered
      manual

      if let status {
        Text(status)
          .font(.custom("Menlo", size: 10.5))
          .foregroundStyle(t.textMuted)
          .lineLimit(5)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        SimuButton(label: "Done") { dismiss() }
      }
    }
    .padding(20)
    .frame(width: 580)
    .background(t.panel)
    .task {
      while !Task.isCancelled {
        await model.refreshMdns()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }

  private var discovered: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("DISCOVERED")
        .font(t.overline)
        .tracking(0.6)
        .foregroundStyle(t.textFaint)

      if model.discoveredServices.isEmpty {
        Text("Looking for pairing services…")
          .font(t.caption)
          .foregroundStyle(t.textFaint)
          .padding(.vertical, 6)
      }

      ForEach(model.discoveredServices) { service in
        HStack(spacing: 10) {
          Image(systemName: "wifi")
            .font(.system(size: 13))
            .foregroundStyle(t.accent)
          VStack(alignment: .leading, spacing: 2) {
            Text("\(service.kind) · \(service.address)")
              .font(.custom("Menlo", size: 11))
              .foregroundStyle(t.text)
            Text(service.name)
              .font(.custom("Menlo", size: 9))
              .foregroundStyle(t.textFaint)
          }
          Spacer()
          if service.isPairing {
            SimuButton(label: "Use") {
              host = service.address
              code = ""
            }
          } else {
            SimuButton(label: "Connect") {
              Task { await connect(service.address) }
            }
          }
        }
        .padding(8)
        .background(
          RoundedRectangle(cornerRadius: SimuTokens.radius)
            .fill(t.raised.opacity(0.5)))
        .overlay(
          RoundedRectangle(cornerRadius: SimuTokens.radius)
            .strokeBorder(t.border, lineWidth: 1))
      }
    }
  }

  private var manual: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("MANUAL")
        .font(t.overline)
        .tracking(0.6)
        .foregroundStyle(t.textFaint)

      HStack(spacing: 8) {
        SimuTextField(text: $host, hint: "192.168.1.5:5555", monospace: true)
        SimuTextField(text: $code, hint: "Pairing code", monospace: true)
          .frame(width: 130)
      }

      HStack(spacing: 8) {
        SimuButton(
          label: "Pair", primary: true,
          action: busy || host.isEmpty || code.count < 6
            ? nil
            : { Task { await pair() } })
        SimuButton(
          label: "Connect",
          action: busy || host.isEmpty ? nil : { Task { await connect(host) } })
        if busy { SimuSpinner() }
      }

      Text(
        "Pairing uses the port shown under Wireless debugging; connecting "
          + "usually uses :5555."
      )
      .font(.custom("Menlo", size: 9))
      .foregroundStyle(t.textFaint)
    }
  }

  private func pair() async {
    busy = true
    defer { busy = false }
    let address = host.trimmingCharacters(in: .whitespaces)
    let pairingCode = code.trimmingCharacters(in: .whitespaces)
    status = await model.pairDevice(hostPort: address, code: pairingCode)
  }

  private func connect(_ address: String) async {
    busy = true
    defer { busy = false }
    status = await model.connectDevice(
      hostPort: address.trimmingCharacters(in: .whitespaces))
  }
}
