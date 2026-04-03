import SwiftUI
import UsefulKeyboardCore

private enum MeetingDocumentMode: Hashable {
    case notes
    case transcript
}

struct MeetingDetailView: View {
    let meeting: MeetingRecord?
    let controller: AppController
    let appState: AppState
    let onBack: (() -> Void)?
    @State private var isSummarizing = false
    @State private var isEditingNotes = false
    @State private var editableTitle: String
    @State private var editableNotes: String
    @State private var pendingTemplateID: String
    @State private var documentMode: MeetingDocumentMode
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var notesSaveTask: DispatchWorkItem?
    @State private var summaryErrorMessage: String?
    @State private var showDeleteConfirmation = false

    init(
        meeting: MeetingRecord?,
        controller: AppController,
        appState: AppState,
        onBack: (() -> Void)? = nil
    ) {
        self.meeting = meeting
        self.controller = controller
        self.appState = appState
        self.onBack = onBack
        let initialTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        _editableTitle = State(initialValue: meeting?.title ?? "")
        _editableNotes = State(initialValue: meeting.map { Self.notesContent(for: $0) } ?? "")
        _pendingTemplateID = State(initialValue: initialTemplateID)
        _documentMode = State(initialValue: meeting.map(Self.defaultDocumentMode(for:)) ?? .notes)
    }

    var body: some View {
        Group {
            if let meeting {
                VStack(alignment: .leading, spacing: 0) {
                    header(meeting)

                    Divider()
                        .background(Theme.surfaceBorder)

                    content(for: meeting)
                }
                .background(Theme.backgroundBase)
                .onChange(of: meeting.id) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: appState.config.customMeetingTemplates) { _, _ in
                    syncPendingTemplateSelectionIfNeeded(for: meeting)
                }
            } else {
                VStack(spacing: Theme.spacing12) {
                    Text("No meeting selected")
                        .font(Theme.title3())
                        .foregroundStyle(Theme.textSecondary)
                    Text("Choose a meeting from the Meetings browser to open it here.")
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.backgroundBase)
            }
        }
        .alert("Couldn't Save Summary", isPresented: summaryErrorBinding) {
            Button("OK", role: .cancel) {
                summaryErrorMessage = nil
            }
        } message: {
            Text(summaryErrorMessage ?? "The updated meeting notes could not be saved.")
        }
        .alert("Delete Meeting", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let meeting {
                    controller.deleteMeeting(id: meeting.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this meeting? Saved notes, transcript, and any retained recording will be removed.")
        }
    }

    @ViewBuilder
    private func header(_ meeting: MeetingRecord) -> some View {
        let appliedTemplate = controller.meetingTemplateSnapshot(for: meeting)
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            // Top toolbar
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "house")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: Theme.spacing8) {
                    documentModePicker
                    templateMenu(for: meeting, appliedTemplate: appliedTemplate)
                    summaryAction(for: meeting)
                    editButton(for: meeting)
                    deleteButton
                }
            }

            // Title
            TextField("Meeting Title", text: $editableTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .onSubmit {
                    controller.updateMeetingTitle(id: meeting.id, title: editableTitle)
                }
                .onChange(of: editableTitle) { _, _ in
                    debounceSaveTitle(meetingID: meeting.id)
                }

            // Metadata chips (Granola-style)
            HStack(spacing: Theme.spacing8) {
                metadataChip(icon: "calendar", text: formatDateChip(meeting.startTime))
                metadataChip(icon: "clock", text: formatDurationChip(meeting.durationSeconds))
                if meeting.wordCount > 0 {
                    metadataChip(icon: "text.word.spacing", text: "\(meeting.wordCount) words")
                }
                templateChip(for: appliedTemplate)
            }

            if isRawTranscript(meeting) && documentMode == .notes {
                transcriptCTA
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.backgroundRaised)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.surfaceBorder, lineWidth: 0.5))
    }

    private func formatDateChip(_ raw: String) -> String {
        guard let date = MeetingBrowserLogic.parseDate(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatDurationChip(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    @ViewBuilder
    private func content(for meeting: MeetingRecord) -> some View {
        if isEditingNotes {
            VStack(alignment: .leading, spacing: Theme.spacing12) {
                contentToolbar(for: meeting)

                TextEditor(text: $editableNotes)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.spacing24)
                    .background(Theme.backgroundBase)
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: editableNotes) { _, _ in
                        debounceSaveNotes(meetingID: meeting.id)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: Theme.spacing12) {
                contentToolbar(for: meeting)

                ZStack {
                    MeetingNotesView(markdown: Self.notesContent(for: meeting))
                        .opacity(documentMode == .notes ? 1 : 0)
                        .allowsHitTesting(documentMode == .notes)
                        .accessibilityHidden(documentMode != .notes)

                    MeetingTranscriptView(transcript: meeting.rawTranscript)
                        .opacity(documentMode == .transcript ? 1 : 0)
                        .allowsHitTesting(documentMode == .transcript)
                        .accessibilityHidden(documentMode != .transcript)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var documentModePicker: some View {
        Picker("", selection: $documentMode) {
            Text("Notes").tag(MeetingDocumentMode.notes)
            Text("Transcript").tag(MeetingDocumentMode.transcript)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .disabled(isEditingNotes)
    }

    @ViewBuilder
    private func summaryAction(for meeting: MeetingRecord) -> some View {
        if isSummarizing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Summarizing...")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacing8)
        } else {
            iconButton("sparkles", label: primarySummaryActionLabel(for: meeting)) {
                isSummarizing = true
                let completion: (Result<Void, Error>) -> Void = { [meeting] result in
                    isSummarizing = false
                    switch result {
                    case .success:
                        if let updated = controller.meeting(id: meeting.id) {
                            syncLocalState(with: updated)
                        }
                    case .failure(let error):
                        syncPendingTemplateSelectionIfNeeded(
                            for: controller.meeting(id: meeting.id) ?? meeting
                        )
                        summaryErrorMessage = error.localizedDescription
                    }
                }
                if hasPendingTemplateChange(for: meeting) {
                    controller.applyMeetingTemplate(id: pendingTemplateID, to: meeting, completion: completion)
                } else {
                    controller.resummarize(meeting: meeting, completion: completion)
                }
            }
        }
    }

    @ViewBuilder
    private func editButton(for meeting: MeetingRecord) -> some View {
        iconButton(
            isEditingNotes ? "checkmark.circle" : "pencil",
            label: isEditingNotes ? "Done" : "Edit"
        ) {
            if isEditingNotes {
                notesSaveTask?.cancel()
                controller.updateMeetingNotes(id: meeting.id, notes: editableNotes)
            } else {
                documentMode = .notes
                editableNotes = Self.notesContent(for: meeting)
            }
            isEditingNotes.toggle()
        }
    }

    @ViewBuilder
    private func recordingAction(for meeting: MeetingRecord) -> some View {
        if let savedRecordingPath = meeting.savedRecordingPath {
            iconButton("folder", label: "Show Recording") {
                controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
            }
        }
    }

    @ViewBuilder
    private func templateMenu(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        Menu {
            Button {
                pendingTemplateID = MeetingTemplates.autoID
            } label: {
                templateMenuItem(
                    title: MeetingTemplates.auto.title,
                    systemImage: MeetingTemplates.auto.icon,
                    isSelected: pendingTemplateID == MeetingTemplates.autoID
                )
            }

            Section("Built-in Templates") {
                ForEach(controller.builtInMeetingTemplates()) { template in
                    Button {
                        pendingTemplateID = template.id
                    } label: {
                        templateMenuItem(
                            title: template.title,
                            systemImage: template.icon,
                            isSelected: pendingTemplateID == template.id
                        )
                    }
                }
            }

            if !controller.customMeetingTemplates().isEmpty {
                Section("Custom Templates") {
                    ForEach(controller.customMeetingTemplates()) { template in
                        Button {
                            pendingTemplateID = template.id
                        } label: {
                            let resolved = MeetingTemplates.customDefinition(from: template)
                            templateMenuItem(
                                title: template.name,
                                systemImage: resolved.icon,
                                isSelected: pendingTemplateID == template.id
                            )
                        }
                    }
                }
            }

            Divider()

            Button("Manage Templates…") {
                controller.showMeetingTemplatesManager()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName(forSelectionOn: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 10))
                Text(labelForSelection(on: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, 5)
            .background(Theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func contentToolbar(for meeting: MeetingRecord) -> some View {
        HStack {
            Spacer()

            Button(action: {
                controller.copyToClipboard(activeCopyText(for: meeting))
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(copyButtonLabel)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.spacing12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall)
                        .fill(Theme.accent.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall)
                        .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private func templateMenuItem(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : systemImage)
                .frame(width: 12)
            Text(title)
        }
    }

    @ViewBuilder
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, 5)
            .background(Theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall)
                    .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        iconButton("trash", label: "Delete") {
            showDeleteConfirmation = true
        }
    }

    @ViewBuilder
    private func templateChip(for snapshot: MeetingTemplateSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: iconName(for: snapshot))
                .font(.system(size: 10))
            Text(snapshot.name)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Theme.spacing8)
        .padding(.vertical, 4)
        .background(Theme.accentSubtle)
        .clipShape(Capsule())
    }

    private var transcriptCTA: some View {
        HStack(spacing: Theme.spacing8) {
            if hasApiKey {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text("Use \(primarySummaryActionLabel) to turn this raw transcript into AI meeting notes and a cleaned-up title.")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(Theme.accent)
                Text("Add your API key in Settings to generate meeting notes")
                    .font(Theme.callout())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Open Settings") {
                    controller.openHistoryWindow(tab: .settings)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.spacing12)
        .background(Theme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
    }

    private var hasApiKey: Bool {
        let config = appState.config
        if appState.selectedMeetingSummaryBackend == .chatGPT {
            return appState.isChatGPTAuthenticated
        } else if appState.selectedMeetingSummaryBackend == .openAI {
            return !config.openAIAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        } else {
            return !config.openRouterAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil
        }
    }

    private var primarySummaryActionLabel: String {
        guard let meeting else { return "Re-summarize" }
        return primarySummaryActionLabel(for: meeting)
    }

    private var copyButtonLabel: String {
        "Copy"
    }

    private func primarySummaryActionLabel(for meeting: MeetingRecord) -> String {
        hasPendingTemplateChange(for: meeting) ? "Apply Template" : "Re-summarize"
    }

    private func activeCopyText(for meeting: MeetingRecord) -> String {
        switch documentMode {
        case .notes:
            return isEditingNotes ? editableNotes : Self.notesContent(for: meeting)
        case .transcript:
            return meeting.rawTranscript
        }
    }

    private func isRawTranscript(_ meeting: MeetingRecord) -> Bool {
        meeting.notesState != .structuredNotes
    }

    private func hasPendingTemplateChange(for meeting: MeetingRecord) -> Bool {
        resolvedPendingTemplateDefinition(for: meeting).id != controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func labelForSelection(on meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return appliedTemplate.name
        }
        return resolvedPendingTemplateDefinition(for: meeting).title
    }

    private func iconName(forSelectionOn meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return iconName(for: appliedTemplate)
        }
        return resolvedPendingTemplateDefinition(for: meeting).icon
    }

    private func iconName(for snapshot: MeetingTemplateSnapshot) -> String {
        switch snapshot.kind {
        case .auto:
            return MeetingTemplates.auto.icon
        case .builtin, .custom:
            return MeetingTemplates.resolveDefinition(
                id: snapshot.id,
                customTemplates: appState.config.customMeetingTemplates
            ).icon
        }
    }

    static func notesContent(for meeting: MeetingRecord) -> String {
        if meeting.notesState != .structuredNotes {
            return "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)"
        }
        return meeting.formattedNotes
    }

    private static func defaultDocumentMode(for meeting: MeetingRecord) -> MeetingDocumentMode {
        meeting.notesState == .structuredNotes ? .notes : .transcript
    }

    private func debounceSaveTitle(meetingID: Int64) {
        titleSaveTask?.cancel()
        let title = editableTitle
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingTitle(id: meetingID, title: title) }
        titleSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func debounceSaveNotes(meetingID: Int64) {
        notesSaveTask?.cancel()
        let notes = editableNotes
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingNotes(id: meetingID, notes: notes) }
        notesSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private var summaryErrorBinding: Binding<Bool> {
        Binding(
            get: { summaryErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    summaryErrorMessage = nil
                }
            }
        )
    }

    private func resolvedPendingTemplateDefinition(for meeting: MeetingRecord) -> MeetingTemplateDefinition {
        if let resolved = MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) {
            return resolved
        }
        return MeetingTemplates.resolveDefinition(
            id: controller.meetingTemplateSnapshot(for: meeting).id,
            customTemplates: appState.config.customMeetingTemplates
        )
    }

    private func syncPendingTemplateSelectionIfNeeded(for meeting: MeetingRecord?) {
        guard let meeting else { return }
        guard MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) == nil else {
            return
        }
        pendingTemplateID = controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func syncLocalState(with meeting: MeetingRecord?) {
        editableTitle = meeting?.title ?? ""
        editableNotes = meeting.map { Self.notesContent(for: $0) } ?? ""
        pendingTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        documentMode = meeting.map(Self.defaultDocumentMode(for:)) ?? .notes
    }

    private func formatMeta(_ meeting: MeetingRecord) -> String {
        let time = formatTime(meeting.startTime)
        let duration = formatDuration(meeting.durationSeconds)
        return "\(time)  \u{2022}  \(duration)  \u{2022}  \(meeting.wordCount) words"
    }

    private func formatTime(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "T", with: " ")
        if clean.count > 16 {
            return String(clean.prefix(16))
        }
        return clean
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return "\(rounded / 3600)h \((rounded % 3600) / 60)m"
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        return "\(rounded)s"
    }
}

private struct MeetingTranscriptView: View {
    let transcript: String

    var body: some View {
        ScrollView {
            Text(transcript)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: 860, alignment: .leading)
                .textSelection(.enabled)
                .padding(Theme.spacing24)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
