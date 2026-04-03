# Branch: feature/context-detection

Read AGENTS.md first for repo context.

## Goal

Before calling Ollama for AI formatting, detect what app the user is dictating into and pass that context to the formatter so it formats appropriately (email style for Mail, casual for Messages, etc.). Also show the detected context as a badge on the floating indicator pill.

## Dependency

**This branch depends on `feature/ollama-formatting` being merged first.**

Before starting, confirm that `OllamaFormatter.swift` exists in `Sources/MuesliNativeApp/`. If it does not exist, stop and report that the dependency branch has not been merged.

Also confirm that `MuesliController.swift` has the Ollama formatting integration (a call to `OllamaFormatter.format()` before `PasteController.paste()`).

## New File: ContextDetector.swift

Create `native/MuesliNative/Sources/MuesliNativeApp/ContextDetector.swift`:

```swift
import AppKit

enum ContextDetector {

    /// Detects the frontmost app and returns a context label for AI formatting.
    /// Returns one of: "email", "imessage", "notes", "ai-prompt", "general"
    static func detectContext() -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            return "general"
        }

        let id = bundleID.lowercased()

        // Email clients
        if id == "com.apple.mail" ||
           id.contains("mimestream") ||
           id.contains("microsoft.outlook") ||
           id.contains("readdle.sparkdesktop") ||
           id.contains("google.gmail") ||
           id.contains("superhuman") {
            return "email"
        }

        // iMessage / Messages
        if id == "com.apple.mobilesms" {
            return "imessage"
        }

        // Chat apps (casual like iMessage)
        if id.contains("slack") ||
           id.contains("microsoft.teams") ||
           id.contains("discord") ||
           id.contains("telegram") ||
           id.contains("whatsapp") {
            return "imessage"
        }

        // Notes apps
        if id == "com.apple.notes" ||
           id.contains("notion") ||
           id.contains("obsidian") ||
           id.contains("bear") {
            return "notes"
        }

        // Browsers and AI apps (likely writing prompts)
        if id.contains("safari") ||
           id.contains("chrome") ||
           id.contains("firefox") ||
           id.contains("arc") ||
           id.contains("anthropic") ||
           id.contains("openai") {
            return "ai-prompt"
        }

        // Code editors (clean, precise)
        if id.contains("xcode") ||
           id.contains("vscode") ||
           id.contains("visual studio") ||
           id.contains("cursor") ||
           id.contains("jetbrains") {
            return "ai-prompt"
        }

        return "general"
    }
}
```

Design decisions:
- `enum` not `struct` — no instances, all static
- Lowercase the bundle ID for case-insensitive matching
- Chat apps (Slack, Teams, Discord) map to `"imessage"` for casual formatting
- Browsers map to `"ai-prompt"` — the most common dictation target in browsers is Claude/ChatGPT
- Code editors also map to `"ai-prompt"` — you're likely dictating a prompt or comment
- Returns `"general"` as the safe default

## Integration: MuesliController.swift

Find where `OllamaFormatter.format()` is called (added by the ollama-formatting branch). It currently passes `context: "general"` (the default). Change it to:

```swift
let context = ContextDetector.detectContext()
let finalText = await OllamaFormatter.format(
    transcript: text,
    context: context,
    model: self.appState.config.ollamaModel
)
```

The `ContextDetector.detectContext()` call must happen on the main thread (NSWorkspace requires it). Since `handleStop()` is already in a `MainActor.run` block, this should work. But verify — if the Ollama call was moved outside the MainActor block, you'll need to capture the context first:

```swift
// On main thread:
let context = ContextDetector.detectContext()
// Then async (can be off main):
let finalText = await OllamaFormatter.format(transcript: text, context: context, model: ...)
// Back on main for paste:
PasteController.paste(text: finalText)
```

## Floating Indicator Badge

File: `Sources/MuesliNativeApp/FloatingIndicatorController.swift`

The floating indicator is an `NSPanel` with custom `NSView` subclass (`HoverIndicatorView`). It has states: idle, recording, transcribing.

Add a context badge that shows during recording:

### Where to add it

The indicator has these layers/subviews:
- `iconLabel` (NSTextField) — shows state icon
- `textLabel` (NSTextField) — shows state text on hover
- Waveform bars (CALayers) — shows during recording

Add a new `NSTextField` for the context badge:

```swift
private var contextLabel: NSTextField?
```

### When to show it

When recording starts (state changes to `.recording`), call `ContextDetector.detectContext()` and set the badge text. The state transitions happen via `setState()` method.

In the `.recording` state setup:
1. Create or update the context label
2. Set its string value to the detected context (e.g., "email", "notes", "general")
3. Position it at the trailing edge of the pill, or below the waveform

### Styling

- Font: 10pt system font, medium weight
- Color: white at 50% opacity (subtle, not distracting)
- No background — just floating text
- Position: right side of the pill, vertically centered, or as a small tag below

### When to hide it

When recording stops (state changes away from `.recording`), hide or remove the context label.

### Implementation sketch

In `FloatingIndicatorController`:

```swift
// Add property
private var contextBadge: NSTextField?

// In the method that sets up the recording state:
func updateContextBadge(_ context: String) {
    if contextBadge == nil {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.5)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        contentView.addSubview(label)
        contextBadge = label
    }
    contextBadge?.stringValue = context
    contextBadge?.sizeToFit()
    // Position at right edge of pill
    // ...
}

// When recording starts:
let context = ContextDetector.detectContext()
updateContextBadge(context)

// When recording stops:
contextBadge?.isHidden = true
```

Look at how the existing `iconLabel` and `textLabel` are positioned and follow the same pattern for layout.

### Where recording state is triggered

The FloatingIndicatorController's state is set from MuesliController. Look for calls like:
```swift
self.indicator.setState(.recording, config: self.config)
```

The context detection should happen at the same time as this state change. Either:
- Add a parameter to setState: `setState(.recording, context: "email", config: ...)`
- Or call a separate method: `self.indicator.updateContextBadge(ContextDetector.detectContext())`

## Files to Create

| File | Purpose |
|---|---|
| `Sources/MuesliNativeApp/ContextDetector.swift` | Frontmost app detection and context mapping |

## Files to Modify

| File | What Changes |
|---|---|
| `Sources/MuesliNativeApp/MuesliController.swift` | Pass detected context to OllamaFormatter.format() |
| `Sources/MuesliNativeApp/FloatingIndicatorController.swift` | Add context badge display during recording |

## Files NOT to Touch

- `Sources/MuesliCore/` (storage)
- `Sources/MuesliCLI/` (CLI)
- Audio/transcription code
- `OllamaFormatter.swift` (do NOT modify — only call it with the context parameter it already accepts)
- Meeting code, CloudKit code
- Package.swift, build scripts
- SettingsView (no new settings needed for context detection)

## Verification

```bash
swift build --package-path native/MuesliNative
swift test --package-path native/MuesliNative
```

Both must pass. Do not modify any existing tests.

## Testing Checklist (manual, after build)

When testing the built app:
1. Open Apple Mail, compose email, dictate — should format as email, pill shows "email"
2. Open Messages, dictate — casual format, pill shows "imessage"  
3. Open Notes, dictate — clean notes, pill shows "notes"
4. Open Safari (navigate to claude.ai), dictate — precise format, pill shows "ai-prompt"
5. Open TextEdit, dictate — general format, pill shows "general"
6. Open Slack, dictate — casual format, pill shows "imessage"
