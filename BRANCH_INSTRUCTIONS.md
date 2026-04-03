# Branch: feature/icloud-sync

Read AGENTS.md first for repo context.

## Goal

Mirror the local SQLite data (dictation history, meetings, meeting folders, and personal dictionary) to a CloudKit private database so it syncs across devices on the same Apple ID. Local-first: always write to SQLite first, sync to CloudKit in the background, never block UI.

## Existing Storage Architecture

### SQLite Database

Location: `~/Library/Application Support/Muesli/muesli.db` (WAL mode)
Code: `native/MuesliNative/Sources/MuesliCore/DictationStore.swift`

#### Table: `dictations`
```sql
CREATE TABLE IF NOT EXISTS dictations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,          -- ISO8601, when dictation ended
    duration_seconds REAL,
    raw_text TEXT,
    app_context TEXT,
    word_count INTEGER NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'dictation',
    started_at TEXT,                  -- ISO8601
    ended_at TEXT,                    -- ISO8601
    created_at TEXT DEFAULT (datetime('now'))
);
```

#### Table: `meetings`
```sql
CREATE TABLE IF NOT EXISTS meetings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    calendar_event_id TEXT,
    start_time TEXT NOT NULL,          -- ISO8601
    end_time TEXT,
    duration_seconds REAL,
    raw_transcript TEXT,
    formatted_notes TEXT,
    mic_audio_path TEXT,               -- local file path, DO NOT sync
    system_audio_path TEXT,            -- local file path, DO NOT sync
    saved_recording_path TEXT,         -- local file path, DO NOT sync
    word_count INTEGER NOT NULL DEFAULT 0,
    selected_template_id TEXT,
    selected_template_name TEXT,
    selected_template_kind TEXT,
    selected_template_prompt TEXT,
    source TEXT NOT NULL DEFAULT 'meeting',
    created_at TEXT DEFAULT (datetime('now')),
    folder_id INTEGER REFERENCES meeting_folders(id)
);
```

#### Table: `meeting_folders`
```sql
CREATE TABLE IF NOT EXISTS meeting_folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);
```

### Data Models

File: `Sources/MuesliCore/StorageModels.swift`

```swift
public struct DictationRecord: Identifiable, Codable, Sendable {
    public let id: Int64
    public let timestamp: String
    public let durationSeconds: Double
    public let rawText: String
    public let appContext: String
    public let wordCount: Int
}

public struct MeetingRecord: Identifiable, Codable, Sendable {
    public let id: Int64
    public let title: String
    public let startTime: String
    public let durationSeconds: Double
    public let rawTranscript: String
    public let formattedNotes: String
    public let wordCount: Int
    public let folderID: Int64?
    public let calendarEventID: String?
    public let micAudioPath: String?
    public let systemAudioPath: String?
    public let savedRecordingPath: String?
    public let selectedTemplateID: String?
    public let selectedTemplateName: String?
    public let selectedTemplateKind: MeetingTemplateKind?
    public let selectedTemplatePrompt: String?
}

public struct MeetingFolder: Identifiable, Codable, Sendable {
    public let id: Int64
    public var name: String
    public let createdAt: String
}
```

### Custom Words (config.json, NOT SQLite)

File: `Sources/MuesliNativeApp/Models.swift`

```swift
struct CustomWord: Codable, Equatable, Identifiable {
    var id = UUID()
    var word: String
    var replacement: String?
}
```

Stored in `AppConfig.customWords` array, persisted to `config.json` via `ConfigStore`.

### Current Entitlements

File: `scripts/Muesli.entitlements`

```xml
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <false/>
    <key>com.apple.security.personal-information.calendars</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
```

No CloudKit entitlements yet.

## Implementation Plan

### 1. Update Entitlements

File: `scripts/Muesli.entitlements`

Add CloudKit container entitlement:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.ai.useful.keyboard</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

### 2. Create CloudKitSyncManager.swift

File: `native/MuesliNative/Sources/MuesliNativeApp/CloudKitSyncManager.swift`

Design:
- Singleton `ObservableObject` for SwiftUI binding
- Container ID: `iCloud.ai.useful.keyboard`
- Uses PRIVATE CloudKit database only (not public, not shared)
- All operations are async, never block UI
- On any CloudKit error: log to stderr and continue silently

CloudKit Record Types to create:

| CK Record Type | Maps To | Key Fields to Sync |
|---|---|---|
| `DictationEntry` | `dictations` table | timestamp, duration_seconds, raw_text, app_context, word_count, started_at, ended_at |
| `MeetingEntry` | `meetings` table | title, start_time, end_time, duration_seconds, raw_transcript, formatted_notes, word_count, calendar_event_id, template fields, folder_id |
| `MeetingFolder` | `meeting_folders` table | name, sort_order |
| `CustomWordEntry` | `AppConfig.customWords` | word, replacement |

**DO NOT sync**: mic_audio_path, system_audio_path, saved_recording_path (these are local file paths that won't exist on other devices)

Record ID strategy:
- Use the local SQLite `id` as part of the CKRecord name (e.g., `"dictation-\(id)"`)
- For custom words, use the UUID `id` field

Key methods:

```swift
class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()
    
    let containerID = "iCloud.ai.useful.keyboard"
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case error(String)
    }
    
    private lazy var container = CKContainer(identifier: containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    
    // Push a single record after local write
    func pushDictation(_ record: DictationRecord) async
    func pushMeeting(_ record: MeetingRecord) async
    func pushFolder(_ folder: MeetingFolder) async
    func pushCustomWords(_ words: [CustomWord]) async
    
    // Pull remote changes (call on launch + periodically)
    func pullChanges() async
    
    // Full bidirectional sync
    func fullSync() async
}
```

For pulls, use `CKFetchRecordZoneChangesOperation` with a stored server change token (save to UserDefaults key `"cloudKitChangeToken"`). This way you only fetch what's new since last pull.

For pushes, use `CKModifyRecordsOperation` with `.changedKeys` save policy to avoid overwriting concurrent changes.

### 3. Hook Into SQLite Writes

File: `Sources/MuesliCore/DictationStore.swift`

The DictationStore is in the `MuesliCore` target which doesn't import CloudKit. Two approaches:

**Option A (Recommended)**: Add a sync callback/delegate that MuesliNativeApp sets. Add a closure property to DictationStore:

```swift
public var onDictationInserted: ((DictationRecord) -> Void)?
public var onMeetingInserted: ((MeetingRecord) -> Void)?
public var onMeetingUpdated: ((Int64) -> Void)?
public var onFolderChanged: (() -> Void)?
```

Set these in `MuesliController` or `AppDelegate` to call `CloudKitSyncManager`.

**Option B**: Use NotificationCenter to post from DictationStore and observe in CloudKitSyncManager.

Either way, the flow is:
1. SQLite write succeeds
2. Fire-and-forget `Task { await CloudKitSyncManager.shared.pushXxx(...) }`
3. Never block the calling thread

### Insert hook locations in DictationStore.swift:

| Method | Approximate Line | Hook |
|---|---|---|
| `insertDictation()` | After sqlite3_step succeeds (~line 333) | `onDictationInserted?(record)` |
| `insertMeeting()` | After sqlite3_step succeeds (~line 337) | `onMeetingInserted?(record)` |
| `updateMeeting()` | After sqlite3_step succeeds (~line 457) | `onMeetingUpdated?(id)` |
| `updateMeetingNotes()` | After sqlite3_step succeeds (~line 472) | `onMeetingUpdated?(id)` |
| `updateMeetingSummary()` | After sqlite3_step succeeds (~line 507) | `onMeetingUpdated?(id)` |
| `updateMeetingTitle()` | After sqlite3_step succeeds (~line 539) | `onMeetingUpdated?(id)` |
| `createFolder()` | After sqlite3_step succeeds (~line 556) | `onFolderChanged?()` |
| `renameFolder()` | After sqlite3_step succeeds (~line 572) | `onFolderChanged?()` |
| `deleteFolder()` | After sqlite3_step succeeds (~line 609) | `onFolderChanged?()` |
| `moveMeeting()` | After sqlite3_step succeeds (~line 649) | `onMeetingUpdated?(id)` |

For custom words, hook into `MuesliController.updateConfig()` (around line 342 in MuesliController.swift) — when `customWords` changes, push to CloudKit.

### 4. Pull on Launch

In `AppDelegate.swift` or `MuesliController` initialization:

```swift
Task {
    await CloudKitSyncManager.shared.pullChanges()
}
```

This runs in the background, does not block app launch.

### 5. Settings UI: Sync Status

File: `Sources/MuesliNativeApp/AboutView.swift`

The About view already has sections like "Support", "Data", "Acknowledgements". Add a line to the data section:

```swift
// In the data/app info section
HStack {
    Text("iCloud Sync")
        .font(MuesliTheme.body())
        .foregroundStyle(MuesliTheme.textPrimary)
    Spacer()
    Text(syncStatusText)
        .font(MuesliTheme.caption())
        .foregroundStyle(MuesliTheme.textSecondary)
}
```

Where `syncStatusText` shows:
- "Last synced 2 min ago" (using `RelativeDateTimeFormatter`)
- "Syncing..." 
- "Never"
- "iCloud unavailable"

Bind to `CloudKitSyncManager.shared.lastSyncDate` and `.syncStatus`.

### 6. Handle Incoming Changes (Pull → SQLite)

When pulling from CloudKit, you need to write incoming records back to SQLite. This means `DictationStore` needs upsert methods:

```swift
// In DictationStore
public func upsertDictation(cloudID: String, record: DictationRecord) throws
public func upsertMeeting(cloudID: String, record: MeetingRecord) throws
public func upsertFolder(cloudID: String, folder: MeetingFolder) throws
```

Use `INSERT OR REPLACE` or check if a record with matching cloud ID exists first. You may want to add a `cloud_record_id TEXT` column to each table to track the CloudKit record name.

### 7. Schema Migration

If you add a `cloud_record_id` column, you'll need to handle the case where the column doesn't exist yet (existing databases). Use `ALTER TABLE ... ADD COLUMN` wrapped in a try/catch, or check the table schema first with `PRAGMA table_info(dictations)`.

## Files to Create

| File | Purpose |
|---|---|
| `Sources/MuesliNativeApp/CloudKitSyncManager.swift` | All CloudKit sync logic |

## Files to Modify

| File | What Changes |
|---|---|
| `scripts/Muesli.entitlements` | Add CloudKit container entitlement |
| `Sources/MuesliCore/DictationStore.swift` | Add sync callbacks after writes, upsert methods, optional cloud_record_id column |
| `Sources/MuesliNativeApp/AboutView.swift` | Add sync status display |
| `Sources/MuesliNativeApp/AppDelegate.swift` or `MuesliController.swift` | Trigger pull on launch, wire up sync callbacks |

## Files NOT to Touch

- Audio/transcription code
- PasteController, HotkeyMonitor
- Meeting recording/detection logic
- SettingsView (sync status goes in AboutView)
- Package.swift (CloudKit is a system framework)
- Build script (except entitlements)

## Important Design Constraints

1. **Local-first always**: SQLite write happens first and must succeed independently of CloudKit.
2. **Never block UI**: All CloudKit operations are `async` and run in background Tasks.
3. **Silent failures**: If iCloud is unavailable (not signed in, no network, quota exceeded), log to stderr and continue. No alerts, no crashes.
4. **Conflict resolution**: Last-writer-wins is acceptable for v1. CloudKit's `.changedKeys` policy handles most cases.
5. **No audio file sync**: Audio recordings are local-only. Only sync text data.
6. **Change tokens**: Store the CloudKit server change token in UserDefaults so pulls are incremental, not full re-downloads.

## Verification

```bash
swift build --package-path native/MuesliNative
swift test --package-path native/MuesliNative
```

Both must pass. Do not modify existing tests. You may add new tests for CloudKitSyncManager if you want, but it's not required since CloudKit operations need a real iCloud account to test.
