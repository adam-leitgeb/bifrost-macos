import SwiftUI

struct UpdatesSection: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater

        VStack(spacing: 0) {
            if let version = updater.availableVersion {
                availableNotice(version)
                Divider()
            }

            Toggle(isOn: $updater.automaticallyChecks) {
                Text("Check for updates automatically")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func availableNotice(_ version: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text("Bifrost \(version) is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Install…") {
                updater.checkForUpdates()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
