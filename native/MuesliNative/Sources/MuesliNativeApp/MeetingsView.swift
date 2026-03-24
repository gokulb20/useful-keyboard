import SwiftUI
import MuesliCore

struct MeetingsView: View {
    let appState: AppState
    let controller: MuesliController

    private var filteredMeetings: [MeetingRecord] {
        guard let folderID = appState.selectedFolderID else {
            return appState.meetingRows
        }
        return appState.meetingRows.filter { $0.folderID == folderID }
    }

    private var currentFolderName: String {
        guard let folderID = appState.selectedFolderID else { return "All Meetings" }
        return appState.folders.first(where: { $0.id == folderID })?.name ?? "All Meetings"
    }

    private var currentDocumentMeeting: MeetingRecord? {
        guard case let .document(id) = appState.meetingsNavigationState else { return nil }
        return appState.meetingRows.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if let meeting = currentDocumentMeeting {
                MeetingDetailView(
                    meeting: meeting,
                    controller: controller,
                    appState: appState,
                    onBack: { controller.showMeetingsHome(folderID: appState.selectedFolderID) }
                )
                .id(meeting.id)
            } else {
                browserView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuesliTheme.backgroundBase)
    }

    @ViewBuilder
    private var browserView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                browserHeader

                if filteredMeetings.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: MuesliTheme.spacing12) {
                        ForEach(filteredMeetings) { meeting in
                            MeetingListItemView(
                                record: meeting,
                                isSelected: appState.selectedMeetingID == meeting.id,
                                folders: appState.folders,
                                onSelect: { controller.showMeetingDocument(id: meeting.id) },
                                onMove: { folderID in
                                    controller.moveMeeting(id: meeting.id, toFolder: folderID)
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var browserHeader: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(currentFolderName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(MuesliTheme.textPrimary)

            HStack(spacing: MuesliTheme.spacing8) {
                Text("\(filteredMeetings.count) meeting\(filteredMeetings.count == 1 ? "" : "s")")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)

                Text("\u{2022}")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)

                Text("Open a meeting to review notes, transcript, and template-driven summaries")
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Image(systemName: appState.selectedFolderID == nil ? "person.2.wave.2" : "folder")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(MuesliTheme.textTertiary)

            Text(appState.selectedFolderID == nil ? "No meetings yet" : "No meetings in this folder")
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textSecondary)

            Text(
                appState.selectedFolderID == nil
                    ? "Start a recording from the menu bar to create your first meeting note."
                    : "Choose another folder or move a meeting here from the browser."
            )
            .font(MuesliTheme.callout())
            .foregroundStyle(MuesliTheme.textTertiary)
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(MuesliTheme.spacing24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }
}
