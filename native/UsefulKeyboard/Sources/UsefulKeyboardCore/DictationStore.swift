import Foundation
import SQLite3

public enum SyncEvent: Sendable {
    case dictationInserted(Int64)
    case meetingInserted(Int64)
    case meetingUpdated(Int64)
    case folderCreated(Int64)
    case folderRenamed(Int64)
    case meetingMoved(Int64)
}

public final class DictationStore {
    private let databaseURL: URL
    public var onSyncEvent: ((SyncEvent) -> Void)?

    public init() {
        self.databaseURL = AppPaths.defaultDatabaseURL()
    }

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public var resolvedDatabaseURL: URL {
        databaseURL
    }

    public var databaseExists: Bool {
        FileManager.default.fileExists(atPath: databaseURL.path)
    }

    public func migrateIfNeeded() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let createSQL = """
        CREATE TABLE IF NOT EXISTS dictations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            duration_seconds REAL,
            raw_text TEXT,
            app_context TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'dictation',
            started_at TEXT,
            ended_at TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_dictations_timestamp ON dictations(timestamp DESC);

        CREATE TABLE IF NOT EXISTS meetings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            calendar_event_id TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            duration_seconds REAL,
            raw_transcript TEXT,
            formatted_notes TEXT,
            mic_audio_path TEXT,
            system_audio_path TEXT,
            saved_recording_path TEXT,
            word_count INTEGER NOT NULL DEFAULT 0,
            selected_template_id TEXT,
            selected_template_name TEXT,
            selected_template_kind TEXT,
            selected_template_prompt TEXT,
            source TEXT NOT NULL DEFAULT 'meeting',
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_meetings_start_time ON meetings(start_time DESC);
        """
        try exec(createSQL, db: db)

        let foldersSQL = """
        CREATE TABLE IF NOT EXISTS meeting_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        );
        """
        try exec(foldersSQL, db: db)

        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN folder_id INTEGER REFERENCES meeting_folders(id)", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        // These template columns are also present in CREATE TABLE for fresh databases.
        // The ALTER TABLE path upgrades pre-existing databases where meetings already exists.
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN selected_template_id TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN selected_template_name TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN selected_template_kind TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN selected_template_prompt TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN saved_recording_path TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        let _ = sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_meetings_folder ON meetings(folder_id)", nil, nil, nil)

        // Context detection columns (stores serialized AppContext as JSON)
        if sqlite3_exec(db, "ALTER TABLE dictations ADD COLUMN context_json TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN context_json TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }

        // iCloud sync columns
        if sqlite3_exec(db, "ALTER TABLE dictations ADD COLUMN cloud_record_id TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meetings ADD COLUMN cloud_record_id TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        if sqlite3_exec(db, "ALTER TABLE meeting_folders ADD COLUMN cloud_record_id TEXT", nil, nil, nil) != SQLITE_OK {
            // Column may already exist.
        }
        let _ = sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_dictations_cloud ON dictations(cloud_record_id)", nil, nil, nil)
        let _ = sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_meetings_cloud ON meetings(cloud_record_id)", nil, nil, nil)
        let _ = sqlite3_exec(db, "CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_cloud ON meeting_folders(cloud_record_id)", nil, nil, nil)
    }

    public func insertDictation(
        text: String,
        durationSeconds: Double,
        appContext: String = "",
        startedAt: Date,
        endedAt: Date,
        contextJSON: String? = nil
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO dictations
        (timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at, context_json)
        VALUES (?, ?, ?, ?, ?, 'dictation', ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        let timestamp = ISO8601DateFormatter().string(from: endedAt)
        let started = ISO8601DateFormatter().string(from: startedAt)
        let ended = ISO8601DateFormatter().string(from: endedAt)
        sqlite3_bind_text(statement, 1, (timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 2, durationSeconds)
        sqlite3_bind_text(statement, 3, (text as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (appContext as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(Self.countWords(in: text)))
        sqlite3_bind_text(statement, 6, (started as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (ended as NSString).utf8String, -1, nil)
        bindOptionalText(contextJSON, at: 8, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        let insertedID = sqlite3_last_insert_rowid(db)
        onSyncEvent?(.dictationInserted(insertedID))
    }

    public func recentDictations(limit: Int = 10, offset: Int = 0, fromDate: String? = nil, toDate: String? = nil) throws -> [DictationRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        var conditions: [String] = []
        var boundValues: [String] = []
        if let fromDate {
            conditions.append("timestamp >= ?")
            boundValues.append(fromDate)
        }
        if let toDate {
            conditions.append("timestamp <= ?")
            boundValues.append(toDate)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let sql = """
        SELECT id, timestamp, duration_seconds, raw_text, app_context, word_count, cloud_record_id
        FROM dictations
        \(whereClause)
        ORDER BY id DESC
        LIMIT ? OFFSET ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in boundValues.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), (value as NSString).utf8String, -1, nil)
        }
        let limitIndex = Int32(boundValues.count + 1)
        let offsetIndex = Int32(boundValues.count + 2)
        sqlite3_bind_int(statement, limitIndex, Int32(limit))
        sqlite3_bind_int(statement, offsetIndex, Int32(offset))

        var rows: [DictationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(makeDictationRecord(statement))
        }
        return rows
    }

    public func dictation(id: Int64) throws -> DictationRecord? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, timestamp, duration_seconds, raw_text, app_context, word_count, cloud_record_id
        FROM dictations
        WHERE id = ?
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return makeDictationRecord(statement)
    }

    public func recentMeetings(limit: Int = 10, folderID: Int64? = nil) throws -> [MeetingRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql: String
        if folderID == nil {
            sql = """
            SELECT id, title, start_time, duration_seconds, raw_transcript, formatted_notes, word_count, folder_id, calendar_event_id, mic_audio_path, system_audio_path, saved_recording_path, selected_template_id, selected_template_name, selected_template_kind, selected_template_prompt, cloud_record_id
            FROM meetings
            ORDER BY id DESC
            LIMIT ?
            """
        } else {
            sql = """
            SELECT id, title, start_time, duration_seconds, raw_transcript, formatted_notes, word_count, folder_id, calendar_event_id, mic_audio_path, system_audio_path, saved_recording_path, selected_template_id, selected_template_name, selected_template_kind, selected_template_prompt, cloud_record_id
            FROM meetings
            WHERE folder_id = ?
            ORDER BY id DESC
            LIMIT ?
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        if let folderID {
            sqlite3_bind_int64(statement, 1, folderID)
            sqlite3_bind_int(statement, 2, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 1, Int32(limit))
        }

        var rows: [MeetingRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(makeMeetingRecord(statement))
        }
        return rows
    }

    public func meeting(id: Int64) throws -> MeetingRecord? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, title, start_time, duration_seconds, raw_transcript, formatted_notes, word_count, folder_id, calendar_event_id, mic_audio_path, system_audio_path, saved_recording_path, selected_template_id, selected_template_name, selected_template_kind, selected_template_prompt, cloud_record_id
        FROM meetings
        WHERE id = ?
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return makeMeetingRecord(statement)
    }

    @discardableResult
    public func insertMeeting(
        title: String,
        calendarEventID: String?,
        startTime: Date,
        endTime: Date,
        rawTranscript: String,
        formattedNotes: String,
        micAudioPath: String?,
        systemAudioPath: String?,
        savedRecordingPath: String? = nil,
        selectedTemplateID: String? = nil,
        selectedTemplateName: String? = nil,
        selectedTemplateKind: MeetingTemplateKind? = nil,
        selectedTemplatePrompt: String? = nil,
        contextJSON: String? = nil
    ) throws -> Int64 {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO meetings
        (title, calendar_event_id, start_time, end_time, duration_seconds, raw_transcript, formatted_notes, mic_audio_path, system_audio_path, saved_recording_path, word_count, selected_template_id, selected_template_name, selected_template_kind, selected_template_prompt, source, context_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'meeting', ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        let formatter = ISO8601DateFormatter()
        let startString = formatter.string(from: startTime)
        let endString = formatter.string(from: endTime)
        let durationSeconds = max(endTime.timeIntervalSince(startTime), 0)
        let wordCount = Self.countWords(in: rawTranscript)

        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        bindOptionalText(calendarEventID, at: 2, statement: statement)
        sqlite3_bind_text(statement, 3, (startString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (endString as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 5, durationSeconds)
        sqlite3_bind_text(statement, 6, (rawTranscript as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (formattedNotes as NSString).utf8String, -1, nil)
        bindOptionalText(micAudioPath, at: 8, statement: statement)
        bindOptionalText(systemAudioPath, at: 9, statement: statement)
        bindOptionalText(savedRecordingPath, at: 10, statement: statement)
        sqlite3_bind_int(statement, 11, Int32(wordCount))
        bindOptionalText(selectedTemplateID, at: 12, statement: statement)
        bindOptionalText(selectedTemplateName, at: 13, statement: statement)
        bindOptionalText(selectedTemplateKind?.rawValue, at: 14, statement: statement)
        bindOptionalText(selectedTemplatePrompt, at: 15, statement: statement)
        bindOptionalText(contextJSON, at: 16, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        let id = sqlite3_last_insert_rowid(db)
        onSyncEvent?(.meetingInserted(id))
        return id
    }

    public func dictationStats() throws -> DictationStats {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            COUNT(*) AS total_sessions,
            COALESCE(SUM(word_count), 0) AS total_words,
            COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds
        FROM dictations
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return DictationStats(totalWords: 0, totalSessions: 0, averageWordsPerSession: 0, averageWPM: 0, currentStreakDays: 0, longestStreakDays: 0)
        }

        let totalSessions = Int(sqlite3_column_int(statement, 0))
        let totalWords = Int(sqlite3_column_int(statement, 1))
        let totalDuration = sqlite3_column_double(statement, 2)
        let streaks = try dictationStreaks(db: db)
        return DictationStats(
            totalWords: totalWords,
            totalSessions: totalSessions,
            averageWordsPerSession: totalSessions > 0 ? Double(totalWords) / Double(totalSessions) : 0,
            averageWPM: totalDuration > 0 ? Double(totalWords) / (totalDuration / 60.0) : 0,
            currentStreakDays: streaks.current,
            longestStreakDays: streaks.longest
        )
    }

    public func meetingStats() throws -> MeetingStats {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            COUNT(*) AS total_meetings,
            COALESCE(SUM(word_count), 0) AS total_words,
            COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds
        FROM meetings
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return MeetingStats(totalWords: 0, totalMeetings: 0, averageWPM: 0)
        }

        let totalMeetings = Int(sqlite3_column_int(statement, 0))
        let totalWords = Int(sqlite3_column_int(statement, 1))
        let totalDuration = sqlite3_column_double(statement, 2)
        return MeetingStats(
            totalWords: totalWords,
            totalMeetings: totalMeetings,
            averageWPM: totalDuration > 0 ? Double(totalWords) / (totalDuration / 60.0) : 0
        )
    }

    public func deleteDictation(id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "DELETE FROM dictations WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        sqlite3_step(statement)
    }

    public func deleteMeeting(id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "DELETE FROM meetings WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    public func clearDictations() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try exec("DELETE FROM dictations", db: db)
    }

    public func clearMeetings() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try exec("DELETE FROM meetings", db: db)
    }

    public func updateMeeting(id: Int64, title: String, formattedNotes: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET title = ?, formatted_notes = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (formattedNotes as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 3, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        onSyncEvent?(.meetingUpdated(id))
    }

    public func updateMeetingNotes(id: Int64, formattedNotes: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET formatted_notes = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (formattedNotes as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        onSyncEvent?(.meetingUpdated(id))
    }

    public func updateMeetingSummary(
        id: Int64,
        title: String,
        formattedNotes: String,
        selectedTemplateID: String,
        selectedTemplateName: String,
        selectedTemplateKind: MeetingTemplateKind,
        selectedTemplatePrompt: String
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = """
        UPDATE meetings
        SET title = ?, formatted_notes = ?, selected_template_id = ?, selected_template_name = ?, selected_template_kind = ?, selected_template_prompt = ?
        WHERE id = ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (formattedNotes as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (selectedTemplateID as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (selectedTemplateName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (selectedTemplateKind.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (selectedTemplatePrompt as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 7, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        onSyncEvent?(.meetingUpdated(id))
    }

    public func updateMeetingTitle(id: Int64, title: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET title = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        onSyncEvent?(.meetingUpdated(id))
    }

    public func updateMeetingSavedRecordingPath(id: Int64, path: String?) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET saved_recording_path = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        bindOptionalText(path, at: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    @discardableResult
    public func createFolder(name: String) throws -> Int64 {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "INSERT INTO meeting_folders (name) VALUES (?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        let id = sqlite3_last_insert_rowid(db)
        onSyncEvent?(.folderCreated(id))
        return id
    }

    public func renameFolder(id: Int64, name: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meeting_folders SET name = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        onSyncEvent?(.folderRenamed(id))
    }

    public func deleteFolder(id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw lastError(db)
        }

        do {
            var s1: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE meetings SET folder_id = NULL WHERE folder_id = ?", -1, &s1, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(s1) }
            sqlite3_bind_int64(s1, 1, id)
            guard sqlite3_step(s1) == SQLITE_DONE else {
                throw lastError(db)
            }

            var s2: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM meeting_folders WHERE id = ?", -1, &s2, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(s2) }
            sqlite3_bind_int64(s2, 1, id)
            guard sqlite3_step(s2) == SQLITE_DONE else {
                throw lastError(db)
            }

            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw lastError(db)
            }
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    public func listFolders() throws -> [MeetingFolder] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "SELECT id, name, created_at, cloud_record_id FROM meeting_folders ORDER BY sort_order ASC, id ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [MeetingFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(MeetingFolder(
                id: sqlite3_column_int64(statement, 0),
                name: stringColumn(statement, index: 1),
                createdAt: stringColumn(statement, index: 2),
                cloudRecordID: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : stringColumn(statement, index: 3)
            ))
        }
        return rows
    }

    public func moveMeeting(id: Int64, toFolder folderID: Int64?) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET folder_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        if let folderID {
            sqlite3_bind_int64(statement, 1, folderID)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
        onSyncEvent?(.meetingMoved(id))
    }

    // MARK: - iCloud Sync Helpers

    public func setCloudRecordID(_ cloudRecordID: String, forDictation id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE dictations SET cloud_record_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (cloudRecordID as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    public func setCloudRecordID(_ cloudRecordID: String, forMeeting id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meetings SET cloud_record_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (cloudRecordID as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    public func setCloudRecordID(_ cloudRecordID: String, forFolder id: Int64) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "UPDATE meeting_folders SET cloud_record_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (cloudRecordID as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError(db)
        }
    }

    public func upsertDictation(
        cloudRecordID: String,
        timestamp: String,
        durationSeconds: Double,
        rawText: String,
        appContext: String,
        startedAt: String?,
        endedAt: String?
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        // Check if record exists
        let check = "SELECT id FROM dictations WHERE cloud_record_id = ? LIMIT 1"
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, check, -1, &checkStmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(checkStmt) }
        sqlite3_bind_text(checkStmt, 1, (cloudRecordID as NSString).utf8String, -1, nil)

        let wordCount = Self.countWords(in: rawText)

        if sqlite3_step(checkStmt) == SQLITE_ROW {
            // Update existing
            let existingID = sqlite3_column_int64(checkStmt, 0)
            let sql = "UPDATE dictations SET timestamp = ?, duration_seconds = ?, raw_text = ?, app_context = ?, word_count = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (timestamp as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, durationSeconds)
            sqlite3_bind_text(stmt, 3, (rawText as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (appContext as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 5, Int32(wordCount))
            sqlite3_bind_int64(stmt, 6, existingID)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        } else {
            // Insert new
            let sql = """
            INSERT INTO dictations (timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at, cloud_record_id)
            VALUES (?, ?, ?, ?, ?, 'dictation', ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (timestamp as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, durationSeconds)
            sqlite3_bind_text(stmt, 3, (rawText as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (appContext as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 5, Int32(wordCount))
            bindOptionalText(startedAt, at: 6, statement: stmt)
            bindOptionalText(endedAt, at: 7, statement: stmt)
            sqlite3_bind_text(stmt, 8, (cloudRecordID as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        }
    }

    public func upsertMeeting(
        cloudRecordID: String,
        title: String,
        startTime: String,
        endTime: String?,
        durationSeconds: Double,
        rawTranscript: String,
        formattedNotes: String,
        calendarEventID: String?,
        selectedTemplateID: String?,
        selectedTemplateName: String?,
        selectedTemplateKind: String?,
        selectedTemplatePrompt: String?,
        folderCloudID: String?
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let wordCount = Self.countWords(in: rawTranscript)

        // Resolve folder_id from folder cloud_record_id
        var folderID: Int64?
        if let folderCloudID {
            let fSql = "SELECT id FROM meeting_folders WHERE cloud_record_id = ? LIMIT 1"
            var fStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, fSql, -1, &fStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(fStmt) }
                sqlite3_bind_text(fStmt, 1, (folderCloudID as NSString).utf8String, -1, nil)
                if sqlite3_step(fStmt) == SQLITE_ROW {
                    folderID = sqlite3_column_int64(fStmt, 0)
                }
            }
        }

        // Check if record exists
        let check = "SELECT id FROM meetings WHERE cloud_record_id = ? LIMIT 1"
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, check, -1, &checkStmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(checkStmt) }
        sqlite3_bind_text(checkStmt, 1, (cloudRecordID as NSString).utf8String, -1, nil)

        if sqlite3_step(checkStmt) == SQLITE_ROW {
            let existingID = sqlite3_column_int64(checkStmt, 0)
            let sql = """
            UPDATE meetings SET title = ?, start_time = ?, end_time = ?, duration_seconds = ?,
            raw_transcript = ?, formatted_notes = ?, word_count = ?, calendar_event_id = ?,
            selected_template_id = ?, selected_template_name = ?, selected_template_kind = ?,
            selected_template_prompt = ?, folder_id = ?
            WHERE id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (startTime as NSString).utf8String, -1, nil)
            bindOptionalText(endTime, at: 3, statement: stmt)
            sqlite3_bind_double(stmt, 4, durationSeconds)
            sqlite3_bind_text(stmt, 5, (rawTranscript as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (formattedNotes as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 7, Int32(wordCount))
            bindOptionalText(calendarEventID, at: 8, statement: stmt)
            bindOptionalText(selectedTemplateID, at: 9, statement: stmt)
            bindOptionalText(selectedTemplateName, at: 10, statement: stmt)
            bindOptionalText(selectedTemplateKind, at: 11, statement: stmt)
            bindOptionalText(selectedTemplatePrompt, at: 12, statement: stmt)
            if let folderID {
                sqlite3_bind_int64(stmt, 13, folderID)
            } else {
                sqlite3_bind_null(stmt, 13)
            }
            sqlite3_bind_int64(stmt, 14, existingID)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        } else {
            let sql = """
            INSERT INTO meetings (title, start_time, end_time, duration_seconds, raw_transcript, formatted_notes,
            word_count, calendar_event_id, selected_template_id, selected_template_name, selected_template_kind,
            selected_template_prompt, folder_id, source, cloud_record_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'meeting', ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (startTime as NSString).utf8String, -1, nil)
            bindOptionalText(endTime, at: 3, statement: stmt)
            sqlite3_bind_double(stmt, 4, durationSeconds)
            sqlite3_bind_text(stmt, 5, (rawTranscript as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (formattedNotes as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 7, Int32(wordCount))
            bindOptionalText(calendarEventID, at: 8, statement: stmt)
            bindOptionalText(selectedTemplateID, at: 9, statement: stmt)
            bindOptionalText(selectedTemplateName, at: 10, statement: stmt)
            bindOptionalText(selectedTemplateKind, at: 11, statement: stmt)
            bindOptionalText(selectedTemplatePrompt, at: 12, statement: stmt)
            if let folderID {
                sqlite3_bind_int64(stmt, 13, folderID)
            } else {
                sqlite3_bind_null(stmt, 13)
            }
            sqlite3_bind_text(stmt, 14, (cloudRecordID as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        }
    }

    public func upsertFolder(cloudRecordID: String, name: String, sortOrder: Int) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let check = "SELECT id FROM meeting_folders WHERE cloud_record_id = ? LIMIT 1"
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, check, -1, &checkStmt, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(checkStmt) }
        sqlite3_bind_text(checkStmt, 1, (cloudRecordID as NSString).utf8String, -1, nil)

        if sqlite3_step(checkStmt) == SQLITE_ROW {
            let existingID = sqlite3_column_int64(checkStmt, 0)
            let sql = "UPDATE meeting_folders SET name = ?, sort_order = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(sortOrder))
            sqlite3_bind_int64(stmt, 3, existingID)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        } else {
            let sql = "INSERT INTO meeting_folders (name, sort_order, cloud_record_id) VALUES (?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError(db)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(sortOrder))
            sqlite3_bind_text(stmt, 3, (cloudRecordID as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw lastError(db)
            }
        }
    }

    public func allDictations() throws -> [DictationRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "SELECT id, timestamp, duration_seconds, raw_text, app_context, word_count, cloud_record_id FROM dictations ORDER BY id ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [DictationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(makeDictationRecord(statement))
        }
        return rows
    }

    public func allMeetings() throws -> [MeetingRecord] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = """
        SELECT id, title, start_time, duration_seconds, raw_transcript, formatted_notes, word_count, folder_id, calendar_event_id, mic_audio_path, system_audio_path, saved_recording_path, selected_template_id, selected_template_name, selected_template_kind, selected_template_prompt, cloud_record_id
        FROM meetings ORDER BY id ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [MeetingRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(makeMeetingRecord(statement))
        }
        return rows
    }

    public func allFolders() throws -> [MeetingFolder] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let sql = "SELECT id, name, created_at, cloud_record_id FROM meeting_folders ORDER BY id ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }
        var rows: [MeetingFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(MeetingFolder(
                id: sqlite3_column_int64(statement, 0),
                name: stringColumn(statement, index: 1),
                createdAt: stringColumn(statement, index: 2),
                cloudRecordID: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : stringColumn(statement, index: 3)
            ))
        }
        return rows
    }

    public func databasePath() -> URL {
        databaseURL
    }

    public static func countWords(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func makeDictationRecord(_ statement: OpaquePointer?) -> DictationRecord {
        DictationRecord(
            id: sqlite3_column_int64(statement, 0),
            timestamp: stringColumn(statement, index: 1),
            durationSeconds: sqlite3_column_double(statement, 2),
            rawText: stringColumn(statement, index: 3),
            appContext: stringColumn(statement, index: 4),
            wordCount: Int(sqlite3_column_int(statement, 5)),
            cloudRecordID: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : stringColumn(statement, index: 6)
        )
    }

    private func makeMeetingRecord(_ statement: OpaquePointer?) -> MeetingRecord {
        let folderID: Int64? = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 7)
        let calendarEventID: String? = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : stringColumn(statement, index: 8)
        let micAudioPath: String? = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : stringColumn(statement, index: 9)
        let systemAudioPath: String? = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : stringColumn(statement, index: 10)
        let savedRecordingPath: String? = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : stringColumn(statement, index: 11)
        let selectedTemplateID: String? = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : stringColumn(statement, index: 12)
        let selectedTemplateName: String? = sqlite3_column_type(statement, 13) == SQLITE_NULL ? nil : stringColumn(statement, index: 13)
        let selectedTemplateKind: MeetingTemplateKind? = sqlite3_column_type(statement, 14) == SQLITE_NULL
            ? nil
            : MeetingTemplateKind(rawValue: stringColumn(statement, index: 14))
        let selectedTemplatePrompt: String? = sqlite3_column_type(statement, 15) == SQLITE_NULL ? nil : stringColumn(statement, index: 15)
        let cloudRecordID: String? = sqlite3_column_type(statement, 16) == SQLITE_NULL ? nil : stringColumn(statement, index: 16)
        return MeetingRecord(
            id: sqlite3_column_int64(statement, 0),
            title: stringColumn(statement, index: 1),
            startTime: stringColumn(statement, index: 2),
            durationSeconds: sqlite3_column_double(statement, 3),
            rawTranscript: stringColumn(statement, index: 4),
            formattedNotes: stringColumn(statement, index: 5),
            wordCount: Int(sqlite3_column_int(statement, 6)),
            folderID: folderID,
            calendarEventID: calendarEventID,
            micAudioPath: micAudioPath,
            systemAudioPath: systemAudioPath,
            savedRecordingPath: savedRecordingPath,
            selectedTemplateID: selectedTemplateID,
            selectedTemplateName: selectedTemplateName,
            selectedTemplateKind: selectedTemplateKind,
            selectedTemplatePrompt: selectedTemplatePrompt,
            cloudRecordID: cloudRecordID
        )
    }

    private func openDatabase() throws -> OpaquePointer? {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw lastError(db)
        }
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
        return db
    }

    private func exec(_ sql: String, db: OpaquePointer?) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw lastError(db)
        }
    }

    private func lastError(_ db: OpaquePointer?) -> NSError {
        NSError(
            domain: "UsefulKeyboardDB",
            code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
        )
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func bindOptionalText(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func dictationStreaks(db: OpaquePointer?) throws -> (current: Int, longest: Int) {
        let sql = "SELECT DISTINCT date(timestamp) AS used_day FROM dictations ORDER BY used_day ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError(db)
        }
        defer { sqlite3_finalize(statement) }

        var days: [Date] = []
        let formatter = ISO8601DateFormatter()
        while sqlite3_step(statement) == SQLITE_ROW {
            let raw = stringColumn(statement, index: 0)
            if let date = formatter.date(from: "\(raw)T00:00:00Z") {
                days.append(date)
            }
        }
        return Self.computeStreak(days: days)
    }

    private static func computeStreak(days: [Date]) -> (current: Int, longest: Int) {
        let calendar = Calendar.current
        let normalized = days
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        guard !normalized.isEmpty else { return (0, 0) }

        var longest = 1
        var run = 1
        for index in 1..<normalized.count {
            let previous = normalized[index - 1]
            let current = normalized[index]
            if let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: current) {
                run += 1
            } else if !calendar.isDate(previous, inSameDayAs: current) {
                longest = max(longest, run)
                run = 1
            }
        }
        longest = max(longest, run)

        let today = calendar.startOfDay(for: Date())
        let anchor: Date
        if calendar.isDate(normalized.last!, inSameDayAs: today) {
            anchor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  calendar.isDate(normalized.last!, inSameDayAs: yesterday) {
            anchor = yesterday
        } else {
            return (0, longest)
        }

        var current = 0
        var cursor = anchor
        let set = Set(normalized)
        while set.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return (current, longest)
    }
}
