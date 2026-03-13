import AppKit
import Foundation

@MainActor
final class RecentHistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: DictationStore
    private let controller: MuesliController

    private let tableDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    private let meetingDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, d MMM • HH:mm"
        return formatter
    }()
    private let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()
    private let localTimestampFallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
    private let utcTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let utcTimestampFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private var window: NSWindow?
    private var dictationTableView: NSTableView?

    private var summaryLabel: NSTextField?
    private var dictationStatsLabel: NSTextField?
    private var meetingStatsLabel: NSTextField?
    private var backendLabel: NSTextField?

    private var meetingSidebarStackView: NSStackView?
    private var meetingTitleLabel: NSTextField?
    private var meetingMetaLabel: NSTextField?
    private var meetingNotesTextView: NSTextView?
    private var copyNotesButton: NSButton?
    private var copyTranscriptButton: NSButton?

    private var dictationRows: [DictationRecord] = []
    private var meetingRows: [MeetingRecord] = []
    private var selectedMeetingID: Int64?
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    init(store: DictationStore, controller: MuesliController) {
        self.store = store
        self.controller = controller
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        guard let window else { return }
        reload()
        if !window.isVisible {
            controller.noteWindowOpened()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func reload() {
        dictationRows = (try? store.recentDictations(limit: 10)) ?? []
        meetingRows = (try? store.recentMeetings(limit: 24)) ?? []
        updateLabels()
        dictationTableView?.reloadData()
        reconcileMeetingSelection()
        rebuildMeetingSidebar()
        renderMeetingSelection()
    }

    func updateBackendLabel() {
        backendLabel?.stringValue = "Backend: \(controller.selectedBackend.label)"
        renderMeetingSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == dictationTableView {
            return dictationRows.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView == dictationTableView else { return nil }
        let identifier = tableColumn?.identifier.rawValue ?? "text"
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell-\(identifier)")
        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.lineBreakMode = .byTruncatingTail
        }

        let item = dictationRows[row]
        textField.stringValue = dictationValue(item, column: identifier)
        return textField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, tableView == dictationTableView else { return }
        let index = tableView.selectedRow
        guard index >= 0, index < dictationRows.count else { return }
        controller.copyToClipboard(dictationRows[index].rawText)
    }

    func windowWillClose(_ notification: Notification) {
        controller.noteWindowClosed()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 140, width: 1120, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.displayName
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = window.contentView!

        let title = NSTextField(labelWithString: "Welcome back to \(AppIdentity.displayName)")
        title.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        title.alignment = .center
        title.frame = NSRect(x: 24, y: 722, width: 1072, height: 32)
        content.addSubview(title)

        let summary = NSTextField(labelWithString: "")
        summary.alignment = .center
        summary.frame = NSRect(x: 24, y: 694, width: 1072, height: 20)
        content.addSubview(summary)
        summaryLabel = summary

        let settingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openPreferences))
        settingsButton.frame = NSRect(x: 500, y: 654, width: 120, height: 28)
        content.addSubview(settingsButton)

        let dictationStats = NSTextField(labelWithString: "")
        dictationStats.alignment = .center
        dictationStats.frame = NSRect(x: 24, y: 618, width: 1072, height: 20)
        content.addSubview(dictationStats)
        dictationStatsLabel = dictationStats

        let meetingStats = NSTextField(labelWithString: "")
        meetingStats.alignment = .center
        meetingStats.frame = NSRect(x: 24, y: 590, width: 1072, height: 20)
        content.addSubview(meetingStats)
        meetingStatsLabel = meetingStats

        let backend = NSTextField(labelWithString: "")
        backend.frame = NSRect(x: 24, y: 566, width: 420, height: 18)
        backend.identifier = NSUserInterfaceItemIdentifier("backendLabel")
        content.addSubview(backend)
        backendLabel = backend

        let tabView = NSTabView(frame: NSRect(x: 24, y: 24, width: 1072, height: 528))
        tabView.autoresizingMask = [.width, .height]
        tabView.addTabViewItem(buildDictationsTab())
        tabView.addTabViewItem(buildMeetingsTab())
        content.addSubview(tabView)

        self.window = window
        updateLabels()
        updateBackendLabel()
    }

    private func buildDictationsTab() -> NSTabViewItem {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1060, height: 490))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let table = NSTableView(frame: scrollView.bounds)
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 32
        table.usesAlternatingRowBackgroundColors = true
        table.autoresizingMask = [.width, .height]

        addColumn("time", title: "Time", width: 160, to: table)
        addColumn("transcript", title: "Transcript", width: 690, to: table)
        addColumn("words", title: "Words", width: 90, to: table)
        addColumn("duration", title: "Duration", width: 100, to: table)

        scrollView.documentView = table
        dictationTableView = table

        let item = NSTabViewItem(identifier: "dictations")
        item.label = "Dictations"
        item.view = scrollView
        return item
    }

    private func buildMeetingsTab() -> NSTabViewItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1060, height: 490))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NotesPalette.canvas.cgColor

        let splitView = NSSplitView(frame: container.bounds)
        splitView.autoresizingMask = [.width, .height]
        splitView.dividerStyle = .thin
        splitView.isVertical = true
        container.addSubview(splitView)

        let sidebarView = buildMeetingsSidebarContainer()
        let detailView = buildMeetingDetailContainer()
        sidebarView.frame = NSRect(x: 0, y: 0, width: 320, height: container.bounds.height)
        detailView.frame = NSRect(x: 328, y: 0, width: container.bounds.width - 328, height: container.bounds.height)
        sidebarView.autoresizingMask = [.height]
        detailView.autoresizingMask = [.width, .height]

        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(detailView)
        splitView.setPosition(320, ofDividerAt: 0)

        let item = NSTabViewItem(identifier: "meetings")
        item.label = "Meetings"
        item.view = container
        return item
    }

    private func buildMeetingsSidebarContainer() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 490))
        container.wantsLayer = true
        container.layer?.backgroundColor = NotesPalette.sidebar.cgColor

        let titleLabel = NSTextField(labelWithString: "Meetings")
        titleLabel.font = AppFonts.bold(26)
        titleLabel.textColor = NotesPalette.primaryText
        titleLabel.frame = NSRect(x: 18, y: 446, width: 180, height: 32)
        container.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Chronological notes")
        subtitleLabel.font = AppFonts.regular(13)
        subtitleLabel.textColor = NotesPalette.secondaryText
        subtitleLabel.frame = NSRect(x: 18, y: 426, width: 180, height: 18)
        container.addSubview(subtitleLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 410))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)

        let documentView = NSView(frame: scrollView.bounds)
        scrollView.documentView = documentView

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        documentView.addSubview(stackView)
        meetingSidebarStackView = stackView

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -12),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -24),
        ])

        return container
    }

    private func buildMeetingDetailContainer() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 490))
        container.wantsLayer = true
        container.layer?.backgroundColor = NotesPalette.canvas.cgColor

        let headerRow = NSView(frame: NSRect(x: 0, y: 412, width: 740, height: 78))
        headerRow.autoresizingMask = [.width, .minYMargin]
        container.addSubview(headerRow)

        let titleLabel = NSTextField(labelWithString: "No meetings yet")
        titleLabel.font = AppFonts.bold(30)
        titleLabel.textColor = NotesPalette.primaryText
        titleLabel.frame = NSRect(x: 28, y: 34, width: 470, height: 36)
        headerRow.addSubview(titleLabel)
        meetingTitleLabel = titleLabel

        let metaLabel = NSTextField(labelWithString: "Recorded meetings will appear here once transcription finishes.")
        metaLabel.font = AppFonts.regular(13)
        metaLabel.textColor = NotesPalette.secondaryText
        metaLabel.frame = NSRect(x: 28, y: 12, width: 520, height: 18)
        headerRow.addSubview(metaLabel)
        meetingMetaLabel = metaLabel

        let copyNotesButton = makeDetailButton(title: "Copy notes", action: #selector(performPrimaryAction))
        copyNotesButton.frame = NSRect(x: 536, y: 30, width: 92, height: 34)
        headerRow.addSubview(copyNotesButton)
        self.copyNotesButton = copyNotesButton

        let copyTranscriptButton = makeDetailButton(title: "Copy transcript", action: #selector(performSecondaryAction))
        copyTranscriptButton.frame = NSRect(x: 636, y: 30, width: 100, height: 34)
        headerRow.addSubview(copyTranscriptButton)
        self.copyTranscriptButton = copyTranscriptButton

        let divider = NSBox(frame: NSRect(x: 24, y: 402, width: 692, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width, .minYMargin]
        container.addSubview(divider)

        let scrollView = NSScrollView(frame: NSRect(x: 18, y: 16, width: 704, height: 376))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)

        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.font = AppFonts.regular(16)
        textView.textColor = NotesPalette.primaryText
        scrollView.documentView = textView
        meetingNotesTextView = textView

        return container
    }

    private func rebuildMeetingSidebar() {
        guard let meetingSidebarStackView else { return }
        meetingSidebarStackView.arrangedSubviews.forEach { view in
            meetingSidebarStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if meetingRows.isEmpty {
            let empty = SidebarMeetingItemView(
                title: "No recorded meetings yet",
                meta: "Start a recording to create your first note.",
                preview: "",
                selected: false
            )
            empty.isUserInteractionEnabled = false
            meetingSidebarStackView.addArrangedSubview(empty)
            return
        }

        for meeting in meetingRows {
            meetingSidebarStackView.addArrangedSubview(makeMeetingListItem(record: meeting))
        }
    }

    private func makeMeetingListItem(record: MeetingRecord) -> SidebarMeetingItemView {
        let item = SidebarMeetingItemView(
            title: record.title,
            meta: "\(displayMeetingTime(record.startTime))  •  \(durationText(seconds: record.durationSeconds))",
            preview: previewText(for: record.formattedNotes.isEmpty ? record.rawTranscript : record.formattedNotes),
            selected: selectedMeetingID == record.id
        )
        item.onSelect = { [weak self] in
            self?.selectMeeting(record.id)
        }
        return item
    }

    private func reconcileMeetingSelection() {
        if let selectedMeetingID, meetingRows.contains(where: { $0.id == selectedMeetingID }) {
            return
        }
        selectedMeetingID = meetingRows.first?.id
    }

    private func selectMeeting(_ id: Int64) {
        selectedMeetingID = id
        rebuildMeetingSidebar()
        renderMeetingSelection()
    }

    private func renderMeetingSelection() {
        guard let selectedMeetingID,
              let meeting = meetingRows.first(where: { $0.id == selectedMeetingID }) else {
            meetingTitleLabel?.stringValue = "No meetings yet"
            meetingMetaLabel?.stringValue = "Recorded meetings will appear here once transcription finishes."
            applyMeetingNotes(makeBodyText("Once a meeting is recorded, its notes will open here like a note document."))
            primaryAction = nil
            secondaryAction = nil
            copyNotesButton?.isHidden = true
            copyTranscriptButton?.isHidden = true
            return
        }

        let notes = meeting.formattedNotes.isEmpty ? "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)" : meeting.formattedNotes
        meetingTitleLabel?.stringValue = meeting.title
        meetingMetaLabel?.stringValue = "\(displayMeetingTime(meeting.startTime))  •  \(durationText(seconds: meeting.durationSeconds))  •  \(meeting.wordCount) words"
        applyMeetingNotes(makeNotesText(notes))

        primaryAction = { [weak self] in
            self?.controller.copyToClipboard(notes)
        }
        secondaryAction = { [weak self] in
            self?.controller.copyToClipboard(meeting.rawTranscript)
        }
        copyNotesButton?.isHidden = false
        copyTranscriptButton?.isHidden = false
    }

    private func applyMeetingNotes(_ attributedText: NSAttributedString) {
        meetingNotesTextView?.textStorage?.setAttributedString(attributedText)
    }

    private func updateLabels() {
        let dictationStats = controller.dictationStats()
        let meetingStats = controller.meetingStats()
        summaryLabel?.stringValue =
            "Streak \(dictationStats.currentStreakDays) days    \(dictationStats.totalWords) dictation words    \(String(format: "%.1f", dictationStats.averageWPM)) WPM"
        dictationStatsLabel?.stringValue =
            "Dictation: \(dictationStats.totalSessions) sessions, \(dictationStats.totalWords) words, \(String(format: "%.1f", dictationStats.averageWordsPerSession)) words/session, longest streak \(dictationStats.longestStreakDays) days"
        meetingStatsLabel?.stringValue =
            "Meetings: \(meetingStats.totalMeetings) meetings, \(meetingStats.totalWords) words, \(String(format: "%.1f", meetingStats.averageWPM)) WPM"
    }

    private func dictationValue(_ item: DictationRecord, column: String) -> String {
        switch column {
        case "time":
            return displayTableTime(item.timestamp)
        case "transcript":
            return controller.truncate(item.rawText, limit: 96)
        case "words":
            return "\(item.wordCount)"
        case "duration":
            return "\(Int(item.durationSeconds.rounded()))s"
        default:
            return ""
        }
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat, to table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        table.addTableColumn(column)
    }

    private func parseRawDate(_ raw: String) -> Date? {
        if let date = utcTimestampFormatter.date(from: raw) ?? utcTimestampFallbackFormatter.date(from: raw) {
            return date
        }
        if let date = localTimestampFormatter.date(from: raw) ?? localTimestampFallbackFormatter.date(from: raw) {
            return date
        }
        return nil
    }

    private func displayTableTime(_ raw: String) -> String {
        guard let date = parseRawDate(raw) else {
            return raw.replacingOccurrences(of: "T", with: " ").prefix(16).description
        }
        return tableDisplayFormatter.string(from: date)
    }

    private func displayMeetingTime(_ raw: String) -> String {
        guard let date = parseRawDate(raw) else {
            return raw.replacingOccurrences(of: "T", with: " ").prefix(16).description
        }
        return meetingDisplayFormatter.string(from: date)
    }

    private func previewText(for text: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard compact.count > 88 else { return compact }
        return String(compact.prefix(85)) + "..."
    }

    private func durationText(seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            let hours = rounded / 3600
            let minutes = (rounded % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
        if rounded >= 60 {
            let minutes = rounded / 60
            let remainder = rounded % 60
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        return "\(rounded)s"
    }

    private func makeBodyText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 12
        return NSAttributedString(
            string: text,
            attributes: [
                .font: AppFonts.regular(16),
                .foregroundColor: NotesPalette.primaryText,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func makeNotesText(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                attributed.append(NSAttributedString(string: "\n"))
                continue
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 10

            let font: NSFont
            let color: NSColor
            let output: String

            if trimmed.hasPrefix("# ") {
                font = AppFonts.bold(28)
                color = NotesPalette.primaryText
                output = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("## ") {
                font = AppFonts.semibold(19)
                color = NotesPalette.primaryText
                output = String(trimmed.dropFirst(3))
            } else if trimmed.hasPrefix("- [ ] ") {
                font = AppFonts.regular(16)
                color = NotesPalette.secondaryText
                output = "□ " + String(trimmed.dropFirst(6))
            } else if trimmed.hasPrefix("- ") {
                font = AppFonts.regular(16)
                color = NotesPalette.secondaryText
                output = "• " + String(trimmed.dropFirst(2))
            } else {
                font = AppFonts.regular(16)
                color = NotesPalette.primaryText
                output = trimmed
            }

            attributed.append(
                NSAttributedString(
                    string: output + "\n",
                    attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph,
                    ]
                )
            )
        }

        if attributed.length == 0 {
            return makeBodyText("Notes unavailable.")
        }
        return attributed
    }

    private func makeDetailButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.backgroundColor = NotesPalette.buttonBackground.cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NotesPalette.buttonBorder.cgColor
        button.contentTintColor = NotesPalette.primaryText
        button.font = AppFonts.medium(13)
        return button
    }

    @objc private func openPreferences() {
        controller.openPreferences()
    }

    @objc private func performPrimaryAction() {
        primaryAction?()
    }

    @objc private func performSecondaryAction() {
        secondaryAction?()
    }
}

private enum NotesPalette {
    static let canvas = NSColor(calibratedRed: 0.115, green: 0.118, blue: 0.122, alpha: 1)
    static let sidebar = NSColor(calibratedRed: 0.094, green: 0.098, blue: 0.104, alpha: 1)
    static let itemBackground = NSColor(calibratedRed: 0.129, green: 0.133, blue: 0.141, alpha: 1)
    static let itemSelected = NSColor(calibratedRed: 0.188, green: 0.204, blue: 0.231, alpha: 1)
    static let itemBorder = NSColor(calibratedWhite: 1, alpha: 0.06)
    static let primaryText = NSColor(calibratedWhite: 0.95, alpha: 1)
    static let secondaryText = NSColor(calibratedWhite: 0.72, alpha: 1)
    static let subtleText = NSColor(calibratedWhite: 0.52, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.72, green: 0.89, blue: 0.99, alpha: 1)
    static let buttonBackground = NSColor(calibratedRed: 0.154, green: 0.158, blue: 0.168, alpha: 1)
    static let buttonBorder = NSColor(calibratedWhite: 1, alpha: 0.08)
}

private final class SidebarMeetingItemView: NSView {
    var onSelect: (() -> Void)?
    var isUserInteractionEnabled = true

    init(title: String, meta: String, preview: String, selected: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = (selected ? NotesPalette.itemSelected : NotesPalette.itemBackground).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (selected ? NotesPalette.accent.withAlphaComponent(0.35) : NotesPalette.itemBorder).cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppFonts.semibold(15)
        titleLabel.textColor = NotesPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        addSubview(titleLabel)

        let metaLabel = NSTextField(labelWithString: meta)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = AppFonts.regular(12)
        metaLabel.textColor = NotesPalette.secondaryText
        addSubview(metaLabel)

        let previewLabel = NSTextField(labelWithString: preview)
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = AppFonts.regular(12)
        previewLabel.textColor = NotesPalette.subtleText
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 2
        addSubview(previewLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            previewLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            previewLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            widthAnchor.constraint(equalToConstant: 292),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard isUserInteractionEnabled else { return }
        onSelect?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isUserInteractionEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
