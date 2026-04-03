# Branch: feature/ollama-formatting

Read AGENTS.md first for repo context.

## Goal

Add an AI formatting post-processing step that sends dictated transcripts to a locally running Ollama instance before pasting. The formatter cleans up grammar, removes remaining filler words, and formats text appropriately. On any failure, it falls back silently to pasting the raw transcript.

## Architecture Overview

The current dictation pipeline flows through:

```
Audio -> Transcription -> FillerWordFilter.apply() -> CustomWordMatcher.apply() -> PasteController.paste()
```

The new pipeline adds one step:

```
Audio -> Transcription -> FillerWordFilter -> CustomWordMatcher -> OllamaFormatter.format() -> PasteController.paste()
```

## The Exact Insertion Point

The paste happens in `MuesliController.swift`. There are two code paths:

### Path 1: Standard (non-streaming) dictation

In `MuesliController.handleStop()` (around line 1309-1314), the current code does:

```swift
await MainActor.run {
    self.statusBarController?.refresh()
    self.historyWindowController?.reload()
    self.syncAppState()
    PasteController.paste(text: text)  // <-- INSERT BEFORE THIS
    self.setState(.idle)
    self.micActivityMonitor.resumeAfterCooldown()
}
```

The variable `text` at this point is the fully processed transcript (filler-filtered, custom-word-matched, trimmed).

### Path 2: Streaming dictation (Nemotron, macOS 15+)

In `MuesliController.handleStop()` for the streaming path (around line 1235-1252):
- `let cleaned = FillerWordFilter.apply(finalText)` produces the final text
- The text is stored to history but has ALREADY been typed incrementally via `onPartialText`
- For streaming, Ollama formatting won't apply to incremental pastes — it could apply as a post-hoc "reformat" of the full text, OR you can skip it for streaming mode

**Recommendation**: For this branch, only apply Ollama formatting to the non-streaming path (Path 1). Add a comment noting that streaming support can be added later.

## New File: OllamaFormatter.swift

Create `native/MuesliNative/Sources/MuesliNativeApp/OllamaFormatter.swift`:

```swift
import Foundation

enum OllamaFormatter {

    static let defaultEndpoint = "http://localhost:11434/api/generate"

    /// Sends transcript to local Ollama for formatting.
    /// Returns the original text unchanged on ANY failure.
    static func format(
        transcript: String,
        context: String = "general",
        model: String,
        timeout: TimeInterval = 10.0
    ) async -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }

        let systemPrompt = """
        You are a text formatter. Clean up this dictated transcript:
        - Fix grammar and punctuation
        - Remove any remaining filler words (uh, um, like, you know)
        - Format appropriately for this context: \(context)
        - Context guidelines:
          - "general": clean prose, natural sentences
          - "email": professional email body, no greeting or sign-off unless spoken
          - "imessage": casual, keep contractions, minimal punctuation
          - "ai-prompt": clear and precise, structured for an AI assistant
          - "notes": bullet points if multiple ideas, otherwise clean prose
        - Return ONLY the formatted text, nothing else
        - Do not add any content that was not in the original
        - Do not explain your changes
        """

        let payload: [String: Any] = [
            "model": model,
            "prompt": transcript,
            "system": systemPrompt,
            "stream": false
        ]

        guard let url = URL(string: defaultEndpoint),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return transcript
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let formatted = json["response"] as? String,
                  !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return transcript
            }
            return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            fputs("[useful-keyboard] Ollama formatting failed: \(error.localizedDescription)\n", stderr)
            return transcript
        }
    }
}
```

Key design decisions:
- `enum` not `class` — no instances needed, all static
- `context` parameter defaults to `"general"` now, but Branch 4 (context-detection) will pass specific values later
- Returns original transcript on ANY failure — never blocks, never crashes
- 10 second timeout
- No external dependencies — pure Foundation URLSession

## Config Changes: Models.swift

File: `Sources/MuesliNativeApp/Models.swift`

The `AppConfig` struct (around line 248) needs new fields. Add these properties:

```swift
var ollamaFormattingEnabled: Bool = true
var ollamaModel: String = "gemma3"
```

Add corresponding `CodingKeys`:
```swift
case ollamaFormattingEnabled = "ollama_formatting_enabled"
case ollamaModel = "ollama_model"
```

Add to the `init(from decoder:)` method following the existing pattern:
```swift
ollamaFormattingEnabled = (try? c.decode(Bool.self, forKey: .ollamaFormattingEnabled)) ?? defaults.ollamaFormattingEnabled
ollamaModel = (try? c.decode(String.self, forKey: .ollamaModel)) ?? defaults.ollamaModel
```

## Integration: MuesliController.swift

In the non-streaming `handleStop()` path, replace the direct paste with:

```swift
// Before pasting, optionally format with Ollama
let finalText: String
if self.appState.config.ollamaFormattingEnabled {
    finalText = await OllamaFormatter.format(
        transcript: text,
        model: self.appState.config.ollamaModel
    )
} else {
    finalText = text
}
PasteController.paste(text: finalText)
```

This needs to be async. The surrounding code is already in an `await MainActor.run` block, but you may need to restructure slightly since `OllamaFormatter.format()` is async. Pull the Ollama call BEFORE the `MainActor.run` block, or use a nested `Task`.

Look at how the existing code is structured and find the cleanest way to insert the async call. The key constraint is: `PasteController.paste()` must run on the main thread, but `OllamaFormatter.format()` can run on any thread.

## Settings UI: SettingsView.swift

File: `Sources/MuesliNativeApp/SettingsView.swift`

The settings view uses helper functions: `settingsSection()`, `settingsRow()`, `settingsSwitch()`, `settingsMenu()`. Follow these patterns exactly.

Add a new section. Find a logical place — after the "Transcription" section or after the existing backend selection would make sense.

```swift
settingsSection("AI Formatting") {
    settingsRow("Enable AI formatting") {
        settingsSwitch(isOn: appState.config.ollamaFormattingEnabled) { newValue in
            controller.updateConfig { $0.ollamaFormattingEnabled = newValue }
        }
    }
    
    if appState.config.ollamaFormattingEnabled {
        Divider().background(MuesliTheme.surfaceBorder)
        settingsRow("Model") {
            TextField("", text: Binding(
                get: { appState.config.ollamaModel },
                set: { val in controller.updateConfig { $0.ollamaModel = val } }
            ))
            .textFieldStyle(.plain)
            .font(MuesliTheme.body())
            .frame(width: 220)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        Divider().background(MuesliTheme.surfaceBorder)
        Text("Requires Ollama running locally at localhost:11434")
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textTertiary)
            .padding(.top, 4)
    }
}
```

The `controller.updateConfig` pattern is used throughout the existing SettingsView — follow it exactly. Look at how other settings use `updateConfig` with a closure that mutates the config.

## Floating Indicator Enhancement (Optional)

If time permits, add a brief "Formatting..." state to the floating indicator while Ollama is processing. The FloatingIndicatorController has a state machine with states like `.recording`, `.transcribing`. You could add a `.formatting` state or reuse `.transcribing` with different text.

This is optional — the core feature works without it.

## Files to Create

| File | Purpose |
|---|---|
| `Sources/MuesliNativeApp/OllamaFormatter.swift` | Ollama API client |

## Files to Modify

| File | What Changes |
|---|---|
| `Sources/MuesliNativeApp/Models.swift` | Add `ollamaFormattingEnabled` and `ollamaModel` to AppConfig |
| `Sources/MuesliNativeApp/MuesliController.swift` | Insert Ollama call before paste in handleStop() |
| `Sources/MuesliNativeApp/SettingsView.swift` | Add AI Formatting settings section |

## Files NOT to Touch

- `Sources/MuesliCore/` (storage)
- `Sources/MuesliCLI/` (CLI)
- Audio files, transcription backends, meeting code
- `PasteController.swift` (don't change paste mechanics, just call it with formatted text)
- `Package.swift` (no new dependencies)
- `scripts/` (no build changes)

## Verification

```bash
swift build --package-path native/MuesliNative
swift test --package-path native/MuesliNative
```

Both must pass. Do not modify any existing tests.
