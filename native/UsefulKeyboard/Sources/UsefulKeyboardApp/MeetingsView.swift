import SwiftUI
import UsefulKeyboardCore

enum MeetingBrowserFilter: Hashable {
    case all, last2Days, lastWeek, last2Weeks, lastMonth, last3Months

    var label: String {
        switch self {
        case .all: return "All time"
        case .last2Days: return "Last 2 days"
        case .lastWeek: return "Last week"
        case .last2Weeks: return "Last 2 weeks"
        case .lastMonth: return "Last month"
        case .last3Months: return "Last 3 months"
        }
    }
}

enum MeetingBrowserSort: Hashable {
    case newestFirst
    case oldestFirst

    var label: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
    }
}

enum MeetingBrowserLogic {
    static func availableFilters(
        for meetings: [MeetingRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingBrowserFilter] {
        var filters: [MeetingBrowserFilter] = [.all]
        let oldestDate = meetings.compactMap { parseDate($0.startTime) }.min()

        guard let oldest = oldestDate else { return filters }
        let daysSinceOldest = calendar.dateComponents([.day], from: oldest, to: now).day ?? 0

        if daysSinceOldest >= 1 { filters.append(.last2Days) }
        if daysSinceOldest >= 3 { filters.append(.lastWeek) }
        if daysSinceOldest >= 8 { filters.append(.last2Weeks) }
        if daysSinceOldest >= 15 { filters.append(.lastMonth) }
        if daysSinceOldest >= 31 { filters.append(.last3Months) }

        return filters
    }

    static func filteredMeetings(
        from meetings: [MeetingRecord],
        filter: MeetingBrowserFilter,
        sort: MeetingBrowserSort,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingRecord] {
        let threshold = threshold(for: filter, now: now, calendar: calendar)
        let filtered = meetings.filter { isAfterThreshold($0, threshold: threshold) }

        return filtered.sorted { lhs, rhs in
            let lhsDate = parseDate(lhs.startTime) ?? .distantPast
            let rhsDate = parseDate(rhs.startTime) ?? .distantPast
            switch sort {
            case .newestFirst:
                return lhsDate > rhsDate
            case .oldestFirst:
                return lhsDate < rhsDate
            }
        }
    }

    private static func threshold(
        for filter: MeetingBrowserFilter,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        switch filter {
        case .all:
            return nil
        case .last2Days:
            return calendar.date(byAdding: .day, value: -2, to: now)
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .last2Weeks:
            return calendar.date(byAdding: .day, value: -14, to: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .last3Months:
            return calendar.date(byAdding: .month, value: -3, to: now)
        }
    }

    private static func isAfterThreshold(_ meeting: MeetingRecord, threshold: Date?) -> Bool {
        guard let threshold else { return true }
        guard let date = parseDate(meeting.startTime) else { return false }
        return date >= threshold
    }

    static func parseDate(_ raw: String) -> Date? {
        isoParsers.lazy.compactMap { $0.date(from: raw) }.first
            ?? localParsers.lazy.compactMap { $0.date(from: raw) }.first
    }

    private static let isoParsers: [ISO8601DateFormatter] = {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return [iso1, iso2]
    }()

    private static let localParsers: [DateFormatter] = {
        let local1: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            return f
        }()
        let local2: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
        return [local1, local2]
    }()
}

struct MeetingsView: View {
    let appState: AppState
    let controller: AppController
    @State private var selectedFilter: MeetingBrowserFilter = .all
    @State private var selectedSort: MeetingBrowserSort = .newestFirst

    private var scopedMeetings: [MeetingRecord] {
        guard let folderID = appState.selectedFolderID else {
            return appState.meetingRows
        }
        return appState.meetingRows.filter { $0.folderID == folderID }
    }

    private var filteredMeetings: [MeetingRecord] {
        if let searchResults = appState.meetingSearchResults {
            return searchResults
        }
        return MeetingBrowserLogic.filteredMeetings(
            from: scopedMeetings,
            filter: selectedFilter,
            sort: selectedSort
        )
    }

    private var currentFolderName: String {
        guard let folderID = appState.selectedFolderID else { return "All Meetings" }
        return appState.folders.first(where: { $0.id == folderID })?.name ?? "All Meetings"
    }

    private var currentDocumentMeeting: MeetingRecord? {
        guard case let .document(id) = appState.meetingsNavigationState else { return nil }
        if appState.selectedMeetingID == id, let selectedMeeting = appState.selectedMeeting {
            return selectedMeeting
        }
        return controller.meeting(id: id)
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
        .background(Theme.backgroundBase)
        .sheet(
            isPresented: Binding(
                get: { appState.isMeetingTemplatesManagerPresented },
                set: { appState.isMeetingTemplatesManagerPresented = $0 }
            )
        ) {
            MeetingTemplatesManagerView(
                appState: appState,
                controller: controller,
                onClose: { appState.isMeetingTemplatesManagerPresented = false }
            )
        }
    }

    @ViewBuilder
    private var browserView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing24) {
                if !appState.dictationReadiness.isReady {
                    SetupBannerView(
                        readiness: appState.dictationReadiness,
                        onNavigateToModels: { appState.selectedTab = .models },
                        onShowOnboarding: { controller.showOnboarding() }
                    )
                }

                browserHeader

                if filteredMeetings.isEmpty {
                    emptyState
                } else {
                    dateGroupedMeetingList
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Date-Grouped Meeting List

    private var groupedMeetings: [(key: String, meetings: [MeetingRecord])] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var groups: [(key: String, meetings: [MeetingRecord])] = []
        var buckets: [String: [MeetingRecord]] = [:]
        var order: [String] = []

        for meeting in filteredMeetings {
            guard let date = MeetingBrowserLogic.parseDate(meeting.startTime) else {
                let key = "Other"
                buckets[key, default: []].append(meeting)
                if !order.contains(key) { order.append(key) }
                continue
            }

            let startOfDay = calendar.startOfDay(for: date)
            let key: String
            if startOfDay == today {
                key = "Today"
            } else if startOfDay == yesterday {
                key = "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE, d MMM"
                key = formatter.string(from: date)
            }

            buckets[key, default: []].append(meeting)
            if !order.contains(key) { order.append(key) }
        }

        for key in order {
            if let meetings = buckets[key] {
                groups.append((key: key, meetings: meetings))
            }
        }
        return groups
    }

    @ViewBuilder
    private var dateGroupedMeetingList: some View {
        LazyVStack(alignment: .leading, spacing: Theme.spacing20) {
            ForEach(groupedMeetings, id: \.key) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.key)
                        .font(Theme.callout())
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 4)
                        .padding(.bottom, 6)

                    ForEach(Array(group.meetings.enumerated()), id: \.element.id) { index, meeting in
                        MeetingListItemView(
                            record: meeting,
                            isSelected: appState.selectedMeetingID == meeting.id,
                            folders: appState.folders,
                            onSelect: { controller.showMeetingDocument(id: meeting.id) },
                            onMove: { folderID in
                                controller.moveMeeting(id: meeting.id, toFolder: folderID)
                            },
                            onDelete: {
                                controller.deleteMeeting(id: meeting.id)
                            }
                        )
                        if index < group.meetings.count - 1 {
                            Divider()
                                .background(Theme.surfaceBorder)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var browserHeader: some View {
        HStack(alignment: .center) {
            Text(currentFolderName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                controller.createQuickNote()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Quick note")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall)
                        .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var sortButton: some View {
        Menu {
            ForEach([MeetingBrowserSort.newestFirst, .oldestFirst], id: \.self) { option in
                Button {
                    selectedSort = option
                } label: {
                    HStack {
                        Text(option.label)
                        if selectedSort == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                Text(selectedSort.label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(selectedSort != .newestFirst ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selectedSort != .newestFirst ? Theme.accent.opacity(0.12) : Theme.surfacePrimary.opacity(0.5))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var dateFilterButton: some View {
        Menu {
            ForEach(availableFilters, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    HStack {
                        Text(filter.label)
                        if selectedFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                if selectedFilter != .all {
                    Text(selectedFilter.label)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(selectedFilter != .all ? Theme.accent : Theme.textTertiary)
            .padding(.horizontal, selectedFilter != .all ? 8 : 0)
            .padding(.vertical, 3)
            .background(selectedFilter != .all ? Theme.accent.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var availableFilters: [MeetingBrowserFilter] {
        MeetingBrowserLogic.availableFilters(for: scopedMeetings)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            Image(systemName: appState.selectedFolderID == nil ? "person.2.wave.2" : "folder")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(Theme.textTertiary)

            Text(appState.selectedFolderID == nil ? "No meetings yet" : "No meetings in this folder")
                .font(Theme.title3())
                .foregroundStyle(Theme.textSecondary)

            Text(
                appState.selectedFolderID == nil
                    ? "Start a recording from the menu bar to create your first meeting note."
                    : "Choose another folder or move a meeting here from the browser."
            )
            .font(Theme.callout())
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(Theme.spacing24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerXL))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerXL)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
        )
    }
}
