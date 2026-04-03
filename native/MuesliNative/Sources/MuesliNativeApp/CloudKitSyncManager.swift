import CloudKit
import Foundation
import MuesliCore

@MainActor
final class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var iCloudAvailable: Bool = false

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case error(String)
        case disabled
    }

    private let container = CKContainer(identifier: "iCloud.ai.useful.keyboard")
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private let zoneName = "MuesliZone"
    private lazy var zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    private var store: DictationStore?
    var onCustomWordsReceived: (([CustomWord]) -> Void)?

    private let changeTokenKey = "com.muesli.cloudkit.changeToken"
    private let initialSyncCompleteKey = "com.muesli.cloudkit.initialSyncComplete"
    private let lastSyncDateKey = "com.muesli.cloudkit.lastSyncDate"
    private let batchSize = 50

    private init() {
        if let date = UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date {
            lastSyncDate = date
        }
    }

    // MARK: - Configuration

    func configure(store: DictationStore) {
        self.store = store
        store.onSyncEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.pushRecord(event: event)
            }
        }
        Task {
            await checkAccountStatus()
            guard iCloudAvailable else { return }
            await createZoneIfNeeded()
            await pullChanges()
            await performInitialSync()
        }
    }

    // MARK: - Account Status

    private func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                iCloudAvailable = true
            default:
                iCloudAvailable = false
                syncStatus = .disabled
            }
        } catch {
            fputs("[muesli-sync] account status check failed: \(error)\n", stderr)
            iCloudAvailable = false
            syncStatus = .disabled
        }
    }

    // MARK: - Zone Management

    private func createZoneIfNeeded() async {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateDB.save(zone)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Zone may already exist, which is fine.
        } catch {
            fputs("[muesli-sync] zone creation failed: \(error)\n", stderr)
        }
    }

    // MARK: - Push

    func pushRecord(event: SyncEvent) async {
        guard iCloudAvailable, let store else { return }

        do {
            switch event {
            case .dictationInserted(let id):
                guard let record = try store.dictation(id: id) else { return }
                let ckRecord = makeCKRecord(from: record)
                let saved = try await privateDB.save(ckRecord)
                try store.setCloudRecordID(saved.recordID.recordName, forDictation: id)

            case .meetingInserted(let id), .meetingUpdated(let id), .meetingMoved(let id):
                guard let record = try store.meeting(id: id) else { return }
                if let cloudID = record.cloudRecordID {
                    // Fetch existing CKRecord to update
                    let recordID = CKRecord.ID(recordName: cloudID, zoneID: zoneID)
                    do {
                        let existing = try await privateDB.record(for: recordID)
                        populateMeetingCKRecord(existing, from: record)
                        try await privateDB.save(existing)
                    } catch let error as CKError where error.code == .unknownItem {
                        // Record was deleted remotely, re-create
                        let ckRecord = makeCKRecord(from: record)
                        let saved = try await privateDB.save(ckRecord)
                        try store.setCloudRecordID(saved.recordID.recordName, forMeeting: id)
                    }
                } else {
                    let ckRecord = makeCKRecord(from: record)
                    let saved = try await privateDB.save(ckRecord)
                    try store.setCloudRecordID(saved.recordID.recordName, forMeeting: id)
                }

            case .folderCreated(let id), .folderRenamed(let id):
                let folders = try store.allFolders()
                guard let folder = folders.first(where: { $0.id == id }) else { return }
                if let cloudID = folder.cloudRecordID {
                    let recordID = CKRecord.ID(recordName: cloudID, zoneID: zoneID)
                    do {
                        let existing = try await privateDB.record(for: recordID)
                        populateFolderCKRecord(existing, from: folder)
                        try await privateDB.save(existing)
                    } catch let error as CKError where error.code == .unknownItem {
                        let ckRecord = makeCKRecord(from: folder)
                        let saved = try await privateDB.save(ckRecord)
                        try store.setCloudRecordID(saved.recordID.recordName, forFolder: id)
                    }
                } else {
                    let ckRecord = makeCKRecord(from: folder)
                    let saved = try await privateDB.save(ckRecord)
                    try store.setCloudRecordID(saved.recordID.recordName, forFolder: id)
                }
            }
        } catch {
            fputs("[muesli-sync] push failed for \(event): \(error)\n", stderr)
            syncStatus = .error("Push failed")
        }
    }

    func pushCustomWords(_ words: [CustomWord]) {
        guard iCloudAvailable else { return }
        Task {
            do {
                var records: [CKRecord] = []
                for word in words {
                    let recordID = CKRecord.ID(recordName: "customword-\(word.id.uuidString)", zoneID: zoneID)
                    let record = CKRecord(recordType: "CustomWordEntry", recordID: recordID)
                    record["word"] = word.word as CKRecordValue
                    record["replacement"] = (word.replacement ?? "") as CKRecordValue
                    records.append(record)
                }

                let operation = CKModifyRecordsOperation(recordsToSave: records)
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .utility
                try await privateDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
            } catch {
                fputs("[muesli-sync] custom words push failed: \(error)\n", stderr)
            }
        }
    }

    // MARK: - Pull

    func pullChanges() async {
        guard iCloudAvailable, let store else { return }
        syncStatus = .syncing

        do {
            let changeToken = loadChangeToken()
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = changeToken

            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])

            var changedRecords: [CKRecord] = []
            var newToken: CKServerChangeToken?

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.recordWasChangedBlock = { _, result in
                    if case .success(let record) = result {
                        changedRecords.append(record)
                    }
                }

                operation.recordZoneFetchResultBlock = { _, result in
                    switch result {
                    case .success((let serverChangeToken, _)):
                        newToken = serverChangeToken
                    case .failure(let error):
                        fputs("[muesli-sync] zone fetch error: \(error)\n", stderr)
                    }
                }

                operation.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                operation.qualityOfService = .utility
                privateDB.add(operation)
            }

            // Process received records
            for record in changedRecords {
                ingestRecord(record, store: store)
            }

            if let newToken {
                saveChangeToken(newToken)
            }

            syncStatus = .idle
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncDateKey)
            MuesliNotifications.postDataDidChange()
        } catch {
            fputs("[muesli-sync] pull failed: \(error)\n", stderr)
            syncStatus = .error("Pull failed")
        }
    }

    // MARK: - Initial Sync (Batch Upload)

    private func performInitialSync() async {
        guard iCloudAvailable, let store else { return }
        guard !UserDefaults.standard.bool(forKey: initialSyncCompleteKey) else { return }

        syncStatus = .syncing

        do {
            // Folders first so meetings can reference them
            let folders = try store.allFolders().filter { $0.cloudRecordID == nil }
            for batch in folders.chunked(into: batchSize) {
                let records = batch.map { makeCKRecord(from: $0) }
                let (saves, _) = try await privateDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
                for (recordID, result) in saves {
                    if case .success = result,
                       let folder = batch.first(where: { "folder-\($0.id)" == recordID.recordName }) {
                        try? store.setCloudRecordID(recordID.recordName, forFolder: folder.id)
                    }
                }
            }

            // Meetings
            let meetings = try store.allMeetings().filter { $0.cloudRecordID == nil }
            for batch in meetings.chunked(into: batchSize) {
                let records = batch.map { makeCKRecord(from: $0) }
                let (saves, _) = try await privateDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
                for (recordID, result) in saves {
                    if case .success = result,
                       let meeting = batch.first(where: { "meeting-\($0.id)" == recordID.recordName }) {
                        try? store.setCloudRecordID(recordID.recordName, forMeeting: meeting.id)
                    }
                }
            }

            // Dictations
            let dictations = try store.allDictations().filter { $0.cloudRecordID == nil }
            for batch in dictations.chunked(into: batchSize) {
                let records = batch.map { makeCKRecord(from: $0) }
                let (saves, _) = try await privateDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
                for (recordID, result) in saves {
                    if case .success = result,
                       let dictation = batch.first(where: { "dictation-\($0.id)" == recordID.recordName }) {
                        try? store.setCloudRecordID(recordID.recordName, forDictation: dictation.id)
                    }
                }
            }

            UserDefaults.standard.set(true, forKey: initialSyncCompleteKey)
            syncStatus = .idle
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncDateKey)
        } catch {
            fputs("[muesli-sync] initial sync failed: \(error)\n", stderr)
            syncStatus = .error("Initial sync failed")
        }
    }

    // MARK: - Record Conversion (Local → CKRecord)

    private func makeCKRecord(from dictation: DictationRecord) -> CKRecord {
        let recordName = dictation.cloudRecordID ?? "dictation-\(dictation.id)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: "DictationEntry", recordID: recordID)
        record["timestamp"] = dictation.timestamp as CKRecordValue
        record["duration_seconds"] = dictation.durationSeconds as CKRecordValue
        record["raw_text"] = dictation.rawText as CKRecordValue
        record["app_context"] = dictation.appContext as CKRecordValue
        record["word_count"] = dictation.wordCount as CKRecordValue
        return record
    }

    private func makeCKRecord(from meeting: MeetingRecord) -> CKRecord {
        let recordName = meeting.cloudRecordID ?? "meeting-\(meeting.id)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: "MeetingEntry", recordID: recordID)
        populateMeetingCKRecord(record, from: meeting)
        return record
    }

    private func populateMeetingCKRecord(_ record: CKRecord, from meeting: MeetingRecord) {
        record["title"] = meeting.title as CKRecordValue
        record["start_time"] = meeting.startTime as CKRecordValue
        record["duration_seconds"] = meeting.durationSeconds as CKRecordValue
        record["raw_transcript"] = meeting.rawTranscript as CKRecordValue
        record["formatted_notes"] = meeting.formattedNotes as CKRecordValue
        record["word_count"] = meeting.wordCount as CKRecordValue
        record["calendar_event_id"] = (meeting.calendarEventID ?? "") as CKRecordValue
        record["selected_template_id"] = (meeting.selectedTemplateID ?? "") as CKRecordValue
        record["selected_template_name"] = (meeting.selectedTemplateName ?? "") as CKRecordValue
        record["selected_template_kind"] = (meeting.selectedTemplateKind?.rawValue ?? "") as CKRecordValue
        record["selected_template_prompt"] = (meeting.selectedTemplatePrompt ?? "") as CKRecordValue
        // Store folder's cloud_record_id for cross-device linking
        if let folderID = meeting.folderID, let store {
            let folders = (try? store.allFolders()) ?? []
            if let folder = folders.first(where: { $0.id == folderID }) {
                record["folder_cloud_id"] = (folder.cloudRecordID ?? "") as CKRecordValue
            }
        }
    }

    private func makeCKRecord(from folder: MeetingFolder) -> CKRecord {
        let recordName = folder.cloudRecordID ?? "folder-\(folder.id)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: "MeetingFolder", recordID: recordID)
        populateFolderCKRecord(record, from: folder)
        return record
    }

    private func populateFolderCKRecord(_ record: CKRecord, from folder: MeetingFolder) {
        record["name"] = folder.name as CKRecordValue
        record["sort_order"] = 0 as CKRecordValue
    }

    // MARK: - Record Ingestion (CKRecord → Local)

    private func ingestRecord(_ record: CKRecord, store: DictationStore) {
        let cloudID = record.recordID.recordName

        switch record.recordType {
        case "DictationEntry":
            let timestamp = record["timestamp"] as? String ?? ""
            let durationSeconds = record["duration_seconds"] as? Double ?? 0
            let rawText = record["raw_text"] as? String ?? ""
            let appContext = record["app_context"] as? String ?? ""
            try? store.upsertDictation(
                cloudRecordID: cloudID,
                timestamp: timestamp,
                durationSeconds: durationSeconds,
                rawText: rawText,
                appContext: appContext,
                startedAt: nil,
                endedAt: nil
            )

        case "MeetingEntry":
            let title = record["title"] as? String ?? ""
            let startTime = record["start_time"] as? String ?? ""
            let endTime = record["end_time"] as? String
            let durationSeconds = record["duration_seconds"] as? Double ?? 0
            let rawTranscript = record["raw_transcript"] as? String ?? ""
            let formattedNotes = record["formatted_notes"] as? String ?? ""
            let calendarEventID = record["calendar_event_id"] as? String
            let selectedTemplateID = record["selected_template_id"] as? String
            let selectedTemplateName = record["selected_template_name"] as? String
            let selectedTemplateKind = record["selected_template_kind"] as? String
            let selectedTemplatePrompt = record["selected_template_prompt"] as? String
            let folderCloudID = record["folder_cloud_id"] as? String
            try? store.upsertMeeting(
                cloudRecordID: cloudID,
                title: title,
                startTime: startTime,
                endTime: endTime,
                durationSeconds: durationSeconds,
                rawTranscript: rawTranscript,
                formattedNotes: formattedNotes,
                calendarEventID: calendarEventID,
                selectedTemplateID: selectedTemplateID,
                selectedTemplateName: selectedTemplateName,
                selectedTemplateKind: selectedTemplateKind,
                selectedTemplatePrompt: selectedTemplatePrompt,
                folderCloudID: folderCloudID
            )

        case "MeetingFolder":
            let name = record["name"] as? String ?? ""
            let sortOrder = record["sort_order"] as? Int ?? 0
            try? store.upsertFolder(cloudRecordID: cloudID, name: name, sortOrder: sortOrder)

        case "CustomWordEntry":
            let word = record["word"] as? String ?? ""
            let replacement = record["replacement"] as? String
            let idString = cloudID.replacingOccurrences(of: "customword-", with: "")
            if let uuid = UUID(uuidString: idString) {
                let customWord = CustomWord(id: uuid, word: word, replacement: replacement)
                onCustomWordsReceived?([customWord])
            }

        default:
            fputs("[muesli-sync] unknown record type: \(record.recordType)\n", stderr)
        }
    }

    // MARK: - Change Token Persistence

    private func saveChangeToken(_ token: CKServerChangeToken?) {
        guard let token else {
            UserDefaults.standard.removeObject(forKey: changeTokenKey)
            return
        }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: changeTokenKey)
    }

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    // MARK: - Remote Notification

    func handleRemoteNotification(userInfo: [String: Any]) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if notification?.notificationType == .recordZone {
            Task {
                await pullChanges()
            }
        }
    }
}

// MARK: - Array Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
