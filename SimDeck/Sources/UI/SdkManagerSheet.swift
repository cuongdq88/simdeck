import SwiftUI

struct SdkManagerSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.simu) private var t

  @State private var tab = 0

  private var installed: [SystemImage] { model.images }

  private var available: [RemoteImage] {
    let installedIDs = Set(installed.map(\.packageId))
    return model.remoteImages.filter { !installedIDs.contains($0.packageId) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      picker
      if !SdkManagerService.licensesAccepted { licenceBanner }
      list
      footer
    }
    .frame(width: 660, height: 580)
    .background(t.panel)
    .task { await model.loadRemoteImages() }
    .overlay(alignment: .topTrailing) {
      NoticePanel(items: model.banners, onDismiss: { model.dismissBanner($0) })
        .padding(14)
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("SDK Manager")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(t.text)
        Text("Android system images")
          .font(t.caption)
          .foregroundStyle(t.textMuted)
      }
      Spacer()
      SimuIconButton(icon: "arrow.clockwise", help: "Reload catalogs", size: 15) {
        Task { await model.loadRemoteImages() }
      }
      SimuIconButton(icon: "xmark", help: "Close", size: 14) { dismiss() }
    }
    .padding(20)
  }

  private var picker: some View {
    HStack(spacing: 8) {
      pickerButton("Installed", count: installed.count, tag: 0)
      pickerButton("Available", count: available.count, tag: 1)
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 12)
  }

  private func pickerButton(_ label: String, count: Int, tag: Int) -> some View {
    Button {
      tab = tag
    } label: {
      HStack(spacing: 6) {
        Text(label).font(.system(size: 12, weight: .semibold))
        Text("\(count)")
          .font(.custom("Menlo", size: 10.5))
          .foregroundStyle(tab == tag ? t.onAccent.opacity(0.7) : t.textFaint)
      }
      .foregroundStyle(tab == tag ? t.onAccent : t.textMuted)
      .frame(height: 26)
      .padding(.horizontal, 12)
      .background(
        RoundedRectangle(cornerRadius: SimuTokens.radiusSmall)
          .fill(tab == tag ? t.accent : t.raised))
      .overlay(
        RoundedRectangle(cornerRadius: SimuTokens.radiusSmall)
          .strokeBorder(tab == tag ? .clear : t.border, lineWidth: 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var licenceBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 13))
        .foregroundStyle(t.warning)
      Text("The SDK licences have not been accepted; installs wait for them.")
        .font(t.caption)
        .foregroundStyle(t.textMuted)
      Spacer()
      SimuButton(label: "Accept licences", primary: true) {
        Task { await model.acceptLicenses() }
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .fill(t.warning.opacity(0.1)))
    .overlay(
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .strokeBorder(t.warning.opacity(0.25), lineWidth: 1))
    .padding(.horizontal, 20)
    .padding(.bottom, 10)
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        if tab == 0 {
          ForEach(installed) { image in
            imageRow(
              title: image.label,
              subtitle: image.packageId,
              trailing: {
                SimuIconButton(icon: "trash", help: "Uninstall", size: 14) {
                  Task { await model.uninstallImage(image.packageId) }
                }
              })
          }
          if installed.isEmpty {
            empty("No system images installed")
          }
        } else {
          if model.loadingRemoteImages && available.isEmpty {
            HStack(spacing: 8) {
              SimuSpinner()
              Text("Reading sdkmanager…").font(t.mono).foregroundStyle(t.textMuted)
            }
            .padding(20)
          }
          ForEach(available) { image in
            imageRow(
              title: image.label,
              subtitle: image.packageId,
              trailing: {
                if model.installing.contains(image.packageId) {
                  VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: model.installProgress[image.packageId] ?? 0)
                      .frame(width: 120)
                    Text(model.installMessage[image.packageId] ?? "")
                      .font(.custom("Menlo", size: 9))
                      .foregroundStyle(t.textFaint)
                      .lineLimit(1)
                  }
                } else {
                  HStack(spacing: 10) {
                    Text(image.size)
                      .font(.custom("Menlo", size: 10))
                      .foregroundStyle(t.textFaint)
                    SimuButton(label: "Install") {
                      Task { await model.installImage(image.packageId) }
                    }
                  }
                }
              })
          }
          if available.isEmpty && !model.loadingRemoteImages {
            empty(
              SdkManagerService.sdkManagerPath == nil
                ? "sdkmanager was not found in the SDK"
                : (SdkManagerService.javaAvailable
                  ? "No downloadable images"
                  : "sdkmanager needs a Java runtime"))
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
  }

  private func imageRow<Trailing: View>(
    title: String, subtitle: String,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(t.label)
          .foregroundStyle(t.text)
          .lineLimit(1)
        Text(subtitle)
          .font(.custom("Menlo", size: 10))
          .foregroundStyle(t.textFaint)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 8)
      trailing()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(RoundedRectangle(cornerRadius: SimuTokens.radius).fill(t.raised.opacity(0.5)))
    .overlay(
      RoundedRectangle(cornerRadius: SimuTokens.radius)
        .strokeBorder(t.border, lineWidth: 1))
  }

  private func empty(_ message: String) -> some View {
    Text(message)
      .font(t.caption)
      .foregroundStyle(t.textMuted)
      .frame(maxWidth: .infinity)
      .padding(24)
  }

  private var footer: some View {
    HStack {
      Text(model.androidHome)
        .font(.custom("Menlo", size: 10))
        .foregroundStyle(t.textFaint)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      SimuButton(label: "Done") { dismiss() }
    }
    .padding(16)
    .overlay(alignment: .top) {
      Rectangle().fill(t.border).frame(height: 1)
    }
  }
}
