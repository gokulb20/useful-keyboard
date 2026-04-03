import SwiftUI
import UsefulKeyboardCore

struct SidebarView: View {
    private let sidebarIconColumnWidth: CGFloat = 20
    private let meetingsTrailingColumnWidth: CGFloat = 24
    private let sidebarRowHorizontalPadding: CGFloat = 16
    private let sidebarRowOuterPadding: CGFloat = 8

    let appState: AppState
    let controller: AppController
    @State private var spacesExpanded = true
    @State private var renamingFolderID: Int64?
    @State private var renamingFolderName = ""
    @State private var folderToDelete: MeetingFolder?
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search
            HStack(spacing: Theme.spacing8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search", text: $searchText)
                    .font(Theme.body())
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .padding(.horizontal, sidebarRowOuterPadding)
            .padding(.top, Theme.spacing16)
            .padding(.bottom, Theme.spacing16)
            .onChange(of: searchText) { _, query in
                appState.meetingSearchQuery = query
                controller.searchMeetings(query: query)
            }

            // Home
            sidebarItem(tab: .meetings, icon: "house.fill", label: "Home") {
                appState.selectedFolderID = nil
                controller.showMeetingsHome()
            }

            Spacer().frame(height: Theme.spacing16)

            // Spaces section
            spacesSection

            Spacer()

            // Bottom toolbar
            HStack(spacing: Theme.spacing16) {
                Spacer()
                bottomButton(icon: "gearshape", tab: .settings)
            }
            .padding(.horizontal, Theme.spacing16)
            .padding(.bottom, Theme.spacing16)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.backgroundDeep)
        .alert(
            "Delete \"\(folderToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                folderToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let folder = folderToDelete {
                    controller.deleteFolder(id: folder.id)
                    controller.showMeetingsHome(folderID: appState.selectedFolderID)
                }
                folderToDelete = nil
            }
        } message: {
            let count = folderToDelete.map { folder in
                appState.meetingRows.filter { $0.folderID == folder.id }.count
            } ?? 0
            if count > 0 {
                Text("\(count) meeting\(count == 1 ? "" : "s") in this folder will be moved to Unfiled.")
            } else {
                Text("This folder will be permanently removed.")
            }
        }
    }

    // MARK: - Spaces Section

    @ViewBuilder
    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        spacesExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: spacesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                        Text("Spaces")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .textCase(.uppercase)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: createNewFolder) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("New Space")
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, 6)
            .padding(.horizontal, sidebarRowOuterPadding)

            if spacesExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    spaceRow(
                        icon: "tray.2",
                        label: "All Meetings",
                        count: appState.meetingRows.count,
                        isSelected: appState.selectedTab == .meetings && appState.selectedFolderID == nil
                    ) {
                        controller.showMeetingsHome()
                    }

                    ForEach(appState.folders) { folder in
                        if renamingFolderID == folder.id {
                            folderRenameField(folder: folder)
                        } else {
                            spaceRow(
                                icon: "folder",
                                label: folder.name,
                                count: appState.meetingRows.filter { $0.folderID == folder.id }.count,
                                isSelected: appState.selectedTab == .meetings && appState.selectedFolderID == folder.id
                            ) {
                                controller.showMeetingsHome(folderID: folder.id)
                            }
                            .contextMenu {
                                Button("Rename") {
                                    renamingFolderID = folder.id
                                    renamingFolderName = folder.name
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    folderToDelete = folder
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, sidebarRowOuterPadding)
            }
        }
    }

    // MARK: - Row Components

    @ViewBuilder
    private func sidebarItem(tab: DashboardTab, icon: String, label: String, action: @escaping () -> Void) -> some View {
        let isSelected = appState.selectedTab == tab && appState.selectedFolderID == nil
        Button(action: action) {
            HStack(spacing: Theme.spacing12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: sidebarIconColumnWidth)
                Text(label)
                    .font(Theme.headline())
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, Theme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .fill(isSelected ? Theme.surfaceSelected : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, sidebarRowOuterPadding)
    }

    private func spaceColor(for name: String) -> Color {
        let hash = abs(name.hashValue)
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .yellow, .mint]
        return colors[hash % colors.count]
    }

    private func spaceIcon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("customer") || lowered.contains("client") { return "person.2" }
        if lowered.contains("intern") || lowered.contains("interview") { return "star" }
        if lowered.contains("standup") || lowered.contains("stand-up") { return "wrench" }
        if lowered.contains("project") { return "square.grid.2x2" }
        if lowered.contains("team") { return "person.3" }
        if lowered.contains("webinar") { return "squares.leading.rectangle" }
        if lowered.contains("note") || lowered.contains("my ") { return "lock" }
        return "folder"
    }

    @ViewBuilder
    private func spaceRow(
        icon: String,
        label: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedIcon = icon == "folder" ? spaceIcon(for: label) : icon
        let iconColor = icon == "folder" ? spaceColor(for: label) : (isSelected ? Theme.accent : Theme.textTertiary)
        HStack(spacing: Theme.spacing8) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: sidebarIconColumnWidth)
            Text(label)
                .font(Theme.callout())
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(Theme.caption())
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: meetingsTrailingColumnWidth, alignment: .center)
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall)
                .fill(isSelected ? Theme.surfaceSelected.opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private func bottomButton(icon: String, tab: DashboardTab) -> some View {
        let isSelected = appState.selectedTab == tab
        Button {
            appState.selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func folderRenameField(folder: MeetingFolder) -> some View {
        HStack(spacing: Theme.spacing8) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: sidebarIconColumnWidth)
            TextField("Space name", text: $renamingFolderName)
                .font(Theme.callout())
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = renamingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        controller.renameFolder(id: folder.id, name: trimmed)
                    }
                    renamingFolderID = nil
                }
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall)
                .fill(Theme.surfaceSelected.opacity(0.6))
        )
    }

    private func createNewFolder() {
        if let id = controller.createFolder(name: "New Space") {
            withAnimation(.easeInOut(duration: 0.15)) {
                spacesExpanded = true
            }
            renamingFolderID = id
            renamingFolderName = "New Space"
            controller.showMeetingsHome(folderID: id)
        }
    }
}
