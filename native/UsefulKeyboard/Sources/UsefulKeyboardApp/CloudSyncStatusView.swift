import SwiftUI

struct CloudSyncStatusView: View {
    @ObservedObject private var syncManager = CloudKitSyncManager.shared

    private var statusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return syncManager.iCloudAvailable ? .green : .gray
        case .syncing:
            return .yellow
        case .error:
            return .red
        case .disabled:
            return .gray
        }
    }

    private var statusLabel: String {
        switch syncManager.syncStatus {
        case .idle:
            return syncManager.iCloudAvailable ? "Synced" : "Not available"
        case .syncing:
            return "Syncing..."
        case .error(let message):
            return message
        case .disabled:
            return "iCloud not available"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            HStack {
                Text("iCloud Sync")
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let lastSync = syncManager.lastSyncDate {
                Text("Last synced \(lastSync, style: .relative) ago")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textTertiary)
            }

            if syncManager.syncStatus == .idle, syncManager.iCloudAvailable {
                Button("Sync Now") {
                    Task {
                        await CloudKitSyncManager.shared.pullChanges()
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.spacing16)
                .padding(.vertical, Theme.spacing8)
                .background(Theme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall)
                        .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
                )
                .buttonStyle(.plain)
            }
        }
    }
}
