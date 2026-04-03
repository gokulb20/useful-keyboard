import SwiftUI
import UsefulKeyboardCore

struct MeetingListItemView: View {
    let record: MeetingRecord
    let isSelected: Bool
    let folders: [MeetingFolder]
    let onSelect: () -> Void
    let onMove: (Int64?) -> Void
    let onDelete: (() -> Void)?
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    private var currentFolderName: String? {
        guard let fid = record.folderID else { return nil }
        return folders.first(where: { $0.id == fid })?.name
    }

    private var avatarColor: Color {
        let hash = abs(record.title.hashValue)
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint
        ]
        return colors[hash % colors.count]
    }

    private var avatarInitial: String {
        let words = record.title.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(record.title.prefix(2)).uppercased()
    }

    var body: some View {
        HStack(spacing: Theme.spacing12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.2))
                Text(avatarInitial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(avatarColor)
            }
            .frame(width: 32, height: 32)

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(Theme.body())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(previewText())
                        .font(Theme.caption())
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Right side: folder badge + actions + time
            HStack(spacing: 8) {
                if let name = currentFolderName, isHovering {
                    folderBadge(name: name)
                }

                if isHovering {
                    actionButtons
                }

                Text(formatTimeOnly(record.startTime))
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .alert("Delete Meeting", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this meeting?")
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func folderBadge(name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9))
            Text(name)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.accentSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 2) {
            if !folders.isEmpty {
                folderMenuButton
            }
            if onDelete != nil {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var folderMenuButton: some View {
        Menu {
            Button {
                onMove(nil)
            } label: {
                Label("Unfiled", systemImage: "tray")
            }
            Divider()
            ForEach(folders) { folder in
                Button {
                    onMove(folder.id)
                } label: {
                    HStack {
                        Label(folder.name, systemImage: "folder")
                        if record.folderID == folder.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Formatting

    private func formatTimeOnly(_ raw: String) -> String {
        guard let date = MeetingBrowserLogic.parseDate(raw) else {
            return raw.count > 5 ? String(raw.suffix(5)) : raw
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func previewText() -> String {
        let source = record.formattedNotes.isEmpty ? record.rawTranscript : record.formattedNotes
        let compact = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if compact.count > 60 {
            return String(compact.prefix(57)) + "..."
        }
        return compact.isEmpty ? formatDuration(record.durationSeconds) : compact
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 60 {
            return "\(rounded / 60)m"
        }
        return "\(rounded)s"
    }
}
