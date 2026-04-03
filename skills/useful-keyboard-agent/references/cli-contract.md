# Useful Keyboard CLI Contract

## Commands

- `useful-keyboard-cli spec`
- `useful-keyboard-cli info`
- `useful-keyboard-cli meetings list [--limit N] [--folder-id ID]`
- `useful-keyboard-cli meetings get <id>`
- `useful-keyboard-cli meetings update-notes <id> (--stdin | --file <path>)`
- `useful-keyboard-cli dictations list [--limit N]`
- `useful-keyboard-cli dictations get <id>`

## Output shape

All commands return JSON to stdout.

Success envelope:
```json
{
  "ok": true,
  "command": "useful-keyboard-cli meetings get",
  "data": {},
  "meta": {
    "schemaVersion": 1,
    "generatedAt": "2026-03-17T00:00:00Z",
    "dbPath": "/Users/example/Library/Application Support/Useful Keyboard/useful-keyboard.db",
    "warnings": []
  }
}
```

Failure envelope:
```json
{
  "ok": false,
  "command": "useful-keyboard-cli meetings get 999",
  "error": {
    "code": "not_found",
    "message": "No meeting exists with id 999.",
    "fix": "Run `useful-keyboard-cli meetings list` to find a valid ID."
  },
  "meta": {
    "schemaVersion": 1,
    "generatedAt": "2026-03-17T00:00:00Z",
    "dbPath": "",
    "warnings": []
  }
}
```

## Important fields

Meeting list rows include:
- `id`
- `title`
- `startTime`
- `durationSeconds`
- `wordCount`
- `folderID`
- `notesState`

Meeting details also include:
- `rawTranscript`
- `formattedNotes`
- `calendarEventID`
- `micAudioPath`
- `systemAudioPath`

`notesState` values:
- `missing`
- `raw_transcript_fallback`
- `structured_notes`

Dictation details include:
- `rawText`
- `appContext`
- `timestamp`
- `durationSeconds`

## Expected agent pattern

- `list` to discover IDs
- `get` to fetch full text
- external summarize/analyze in the coding agent
- `update-notes` to write notes back
