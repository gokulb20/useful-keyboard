import Testing
import Foundation
import UsefulKeyboardCore
import SQLite3

@Suite("CloudKit Sync", .serialized)
struct CloudKitSyncTests {

    private func makeStore() throws -> DictationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-sync-test-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        return store
    }

    // MARK: - Schema Migration

    @Test("migration adds cloud_record_id columns")
    func migrationAddsCloudColumns() throws {
        let store = try makeStore()
        // Verify columns exist by attempting to set them
        try store.insertDictation(
            text: "test", durationSeconds: 1.0, startedAt: Date(), endedAt: Date()
        )
        let dictations = try store.allDictations()
        #expect(dictations.count == 1)
        #expect(dictations[0].cloudRecordID == nil)
    }

    @Test("migration is idempotent with cloud columns")
    func migrationIdempotent() throws {
        let store = try makeStore()
        try store.migrateIfNeeded() // second call should not error
        try store.migrateIfNeeded() // third call
    }

    // MARK: - setCloudRecordID

    @Test("setCloudRecordID for dictation persists and reads back")
    func setCloudRecordIDDictation() throws {
        let store = try makeStore()
        try store.insertDictation(
            text: "hello", durationSeconds: 2.0, startedAt: Date(), endedAt: Date()
        )
        let dictations = try store.allDictations()
        let id = dictations[0].id
        #expect(dictations[0].cloudRecordID == nil)

        try store.setCloudRecordID("dictation-abc-123", forDictation: id)

        let updated = try store.dictation(id: id)
        #expect(updated?.cloudRecordID == "dictation-abc-123")
    }

    @Test("setCloudRecordID for meeting persists and reads back")
    func setCloudRecordIDMeeting() throws {
        let store = try makeStore()
        let id = try store.insertMeeting(
            title: "Test Meeting",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            rawTranscript: "hello world",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )
        #expect((try store.meeting(id: id))?.cloudRecordID == nil)

        try store.setCloudRecordID("meeting-xyz", forMeeting: id)

        let updated = try store.meeting(id: id)
        #expect(updated?.cloudRecordID == "meeting-xyz")
    }

    @Test("setCloudRecordID for folder persists and reads back")
    func setCloudRecordIDFolder() throws {
        let store = try makeStore()
        let id = try store.createFolder(name: "Work")

        try store.setCloudRecordID("folder-999", forFolder: id)

        let folders = try store.allFolders()
        let folder = folders.first(where: { $0.id == id })
        #expect(folder?.cloudRecordID == "folder-999")
    }

    // MARK: - Upsert Methods

    @Test("upsertDictation inserts new record with cloud ID")
    func upsertDictationInsert() throws {
        let store = try makeStore()
        try store.upsertDictation(
            cloudRecordID: "cloud-dict-1",
            timestamp: "2026-01-01T00:00:00Z",
            durationSeconds: 5.0,
            rawText: "hello from cloud",
            appContext: "Slack",
            startedAt: nil,
            endedAt: nil
        )

        let all = try store.allDictations()
        #expect(all.count == 1)
        #expect(all[0].cloudRecordID == "cloud-dict-1")
        #expect(all[0].rawText == "hello from cloud")
    }

    @Test("upsertDictation updates existing record by cloud ID")
    func upsertDictationUpdate() throws {
        let store = try makeStore()
        try store.upsertDictation(
            cloudRecordID: "cloud-dict-2",
            timestamp: "2026-01-01T00:00:00Z",
            durationSeconds: 5.0,
            rawText: "original text",
            appContext: "",
            startedAt: nil,
            endedAt: nil
        )

        try store.upsertDictation(
            cloudRecordID: "cloud-dict-2",
            timestamp: "2026-01-01T00:00:00Z",
            durationSeconds: 5.0,
            rawText: "updated text",
            appContext: "",
            startedAt: nil,
            endedAt: nil
        )

        let all = try store.allDictations()
        #expect(all.count == 1)
        #expect(all[0].rawText == "updated text")
    }

    @Test("upsertFolder inserts new folder with cloud ID")
    func upsertFolderInsert() throws {
        let store = try makeStore()
        try store.upsertFolder(cloudRecordID: "cloud-folder-1", name: "Projects", sortOrder: 0)

        let folders = try store.allFolders()
        #expect(folders.count == 1)
        #expect(folders[0].cloudRecordID == "cloud-folder-1")
        #expect(folders[0].name == "Projects")
    }

    @Test("upsertFolder updates existing folder by cloud ID")
    func upsertFolderUpdate() throws {
        let store = try makeStore()
        try store.upsertFolder(cloudRecordID: "cloud-folder-2", name: "Old Name", sortOrder: 0)
        try store.upsertFolder(cloudRecordID: "cloud-folder-2", name: "New Name", sortOrder: 1)

        let folders = try store.allFolders()
        #expect(folders.count == 1)
        #expect(folders[0].name == "New Name")
    }

    @Test("upsertMeeting inserts new meeting with cloud ID")
    func upsertMeetingInsert() throws {
        let store = try makeStore()
        try store.upsertMeeting(
            cloudRecordID: "cloud-meeting-1",
            title: "Standup",
            startTime: "2026-01-01T09:00:00Z",
            endTime: "2026-01-01T09:30:00Z",
            durationSeconds: 1800,
            rawTranscript: "discussion points",
            formattedNotes: "",
            calendarEventID: nil,
            selectedTemplateID: nil,
            selectedTemplateName: nil,
            selectedTemplateKind: nil,
            selectedTemplatePrompt: nil,
            folderCloudID: nil
        )

        let meetings = try store.allMeetings()
        #expect(meetings.count == 1)
        #expect(meetings[0].cloudRecordID == "cloud-meeting-1")
        #expect(meetings[0].title == "Standup")
    }

    // MARK: - Sync Event Callbacks

    @Test("onSyncEvent fires for insertDictation")
    func syncEventDictation() throws {
        let store = try makeStore()
        var receivedEvent: SyncEvent?
        store.onSyncEvent = { event in
            receivedEvent = event
        }

        try store.insertDictation(
            text: "test", durationSeconds: 1.0, startedAt: Date(), endedAt: Date()
        )

        if case .dictationInserted(let id) = receivedEvent {
            #expect(id > 0)
        } else {
            Issue.record("Expected dictationInserted event")
        }
    }

    @Test("onSyncEvent fires for insertMeeting")
    func syncEventMeeting() throws {
        let store = try makeStore()
        var receivedEvent: SyncEvent?
        store.onSyncEvent = { event in
            receivedEvent = event
        }

        let id = try store.insertMeeting(
            title: "Test",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            rawTranscript: "test",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )

        if case .meetingInserted(let eventID) = receivedEvent {
            #expect(eventID == id)
        } else {
            Issue.record("Expected meetingInserted event")
        }
    }

    @Test("onSyncEvent fires for createFolder")
    func syncEventFolder() throws {
        let store = try makeStore()
        var receivedEvent: SyncEvent?
        store.onSyncEvent = { event in
            receivedEvent = event
        }

        let id = try store.createFolder(name: "Test Folder")

        if case .folderCreated(let eventID) = receivedEvent {
            #expect(eventID == id)
        } else {
            Issue.record("Expected folderCreated event")
        }
    }

    @Test("nil onSyncEvent does not crash")
    func nilSyncEvent() throws {
        let store = try makeStore()
        // onSyncEvent is nil by default — should not crash
        try store.insertDictation(
            text: "test", durationSeconds: 1.0, startedAt: Date(), endedAt: Date()
        )
        _ = try store.insertMeeting(
            title: "Test",
            calendarEventID: nil,
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            rawTranscript: "test",
            formattedNotes: "",
            micAudioPath: nil,
            systemAudioPath: nil
        )
        _ = try store.createFolder(name: "Test")
    }

    // MARK: - Batch Queries

    @Test("allDictations returns all records")
    func allDictationsReturnsAll() throws {
        let store = try makeStore()
        for i in 0..<25 {
            try store.insertDictation(
                text: "dictation \(i)", durationSeconds: 1.0, startedAt: Date(), endedAt: Date()
            )
        }
        let all = try store.allDictations()
        #expect(all.count == 25)
    }

    @Test("allMeetings returns all records")
    func allMeetingsReturnsAll() throws {
        let store = try makeStore()
        for i in 0..<10 {
            _ = try store.insertMeeting(
                title: "Meeting \(i)",
                calendarEventID: nil,
                startTime: Date(),
                endTime: Date().addingTimeInterval(60),
                rawTranscript: "test",
                formattedNotes: "",
                micAudioPath: nil,
                systemAudioPath: nil
            )
        }
        let all = try store.allMeetings()
        #expect(all.count == 10)
    }

    @Test("allFolders returns all records")
    func allFoldersReturnsAll() throws {
        let store = try makeStore()
        _ = try store.createFolder(name: "A")
        _ = try store.createFolder(name: "B")
        _ = try store.createFolder(name: "C")
        let all = try store.allFolders()
        #expect(all.count == 3)
    }

    // MARK: - Meeting-Folder Linking via Cloud IDs

    @Test("upsertMeeting resolves folder via cloud ID")
    func meetingFolderLinkingViaCloudID() throws {
        let store = try makeStore()
        // Create a folder with a cloud ID
        try store.upsertFolder(cloudRecordID: "cloud-folder-link", name: "Linked Folder", sortOrder: 0)

        // Create a meeting referencing that folder's cloud ID
        try store.upsertMeeting(
            cloudRecordID: "cloud-meeting-linked",
            title: "Linked Meeting",
            startTime: "2026-01-01T09:00:00Z",
            endTime: nil,
            durationSeconds: 600,
            rawTranscript: "test",
            formattedNotes: "",
            calendarEventID: nil,
            selectedTemplateID: nil,
            selectedTemplateName: nil,
            selectedTemplateKind: nil,
            selectedTemplatePrompt: nil,
            folderCloudID: "cloud-folder-link"
        )

        let meetings = try store.allMeetings()
        let meeting = meetings.first(where: { $0.cloudRecordID == "cloud-meeting-linked" })
        #expect(meeting != nil)

        // The meeting should have the local folder_id set
        let folders = try store.allFolders()
        let folder = folders.first(where: { $0.cloudRecordID == "cloud-folder-link" })
        #expect(folder != nil)
        #expect(meeting?.folderID == folder?.id)
    }
}
