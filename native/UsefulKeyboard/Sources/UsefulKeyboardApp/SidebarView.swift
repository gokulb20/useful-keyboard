import SwiftUI
import UsefulKeyboardCore

struct SidebarView: View {
    private let sidebarIconColumnWidth: CGFloat = 20
    private let meetingsTrailingColumnWidth: CGFloat = 24
    private let sidebarRowHorizontalPadding: CGFloat = 16
    private let sidebarRowOuterPadding: CGFloat = 8

    let appState: AppState
    let controller: AppController
    @State private var meetingsExpanded = true
    @State private var renamingFolderID: Int64?
    @State private var renamingFolderName = ""
    @State private var folderToDelete: MeetingFolder?
    @State private var showDeleteConfirmation = false

    private var userName: String {
        appState.config.userName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            sidebarHeader

            sidebarItem(tab: .dictations, icon: "mic.fill", label: "Dictations")
            meetingsSection
            sidebarItem(tab: .dictionary, icon: "character.book.closed", label: "Dictionary")
            sidebarItem(tab: .models, icon: "square.and.arrow.down", label: "Models")
            sidebarItem(tab: .shortcuts, icon: "keyboard", label: "Shortcuts")

            Spacer()

            sidebarItem(tab: .settings, icon: "gearshape", label: "Settings")
            sidebarItem(tab: .about, icon: "info.circle", label: "About")
                .padding(.bottom, Theme.spacing16)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.backgroundDeep)
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .meetings {
                meetingsExpanded = true
            }
        }
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

    @ViewBuilder
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack(spacing: Theme.spacing12) {
                WaveformIcon(barCount: 9, spacing: 2)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.accent)
                Text("useful keyboard")
                    .font(Theme.title2())
                    .foregroundStyle(Theme.textPrimary)
            }
            if !userName.isEmpty {
                Text("Hi, \(userName)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.top, Theme.spacing24)
        .padding(.bottom, Theme.spacing20)
    }

    @ViewBuilder
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            let isSelected = appState.selectedTab == .meetings
            HStack(spacing: Theme.spacing12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        meetingsExpanded = true
                    }
                    controller.showMeetingsHome()
                } label: {
                    HStack(spacing: Theme.spacing12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                            .frame(width: sidebarIconColumnWidth)
                        Text("Meetings")
                            .font(Theme.headline())
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        meetingsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: meetingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.textSecondary : Theme.textTertiary)
                        .frame(width: meetingsTrailingColumnWidth, height: 18)
                }
                .buttonStyle(.plain)

                Button(action: createNewFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.textSecondary : Theme.textTertiary)
                        .frame(width: meetingsTrailingColumnWidth, height: 18)
                }
                .buttonStyle(.plain)
                .help("New Meeting Folder")
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, Theme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .fill(isSelected ? Theme.surfaceSelected : Color.clear)
            )
            .padding(.horizontal, sidebarRowOuterPadding)

            if meetingsExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    meetingFilterRow(
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
                            meetingFilterRow(
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

    @ViewBuilder
    private func sidebarItem(tab: DashboardTab, icon: String, label: String) -> some View {
        let isSelected = appState.selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedTab = tab
            }
        } label: {
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

    @ViewBuilder
    private func meetingFilterRow(
        icon: String,
        label: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
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
    private func folderRenameField(folder: MeetingFolder) -> some View {
        HStack(spacing: Theme.spacing8) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: sidebarIconColumnWidth)
            TextField("Folder name", text: $renamingFolderName)
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
        if let id = controller.createFolder(name: "New Folder") {
            withAnimation(.easeInOut(duration: 0.15)) {
                meetingsExpanded = true
            }
            renamingFolderID = id
            renamingFolderName = "New Folder"
            controller.showMeetingsHome(folderID: id)
        }
    }
}
