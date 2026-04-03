# Useful Keyboard — Agent Context

This is a fork of Muesli (https://github.com/pHequals7/muesli), a local-first
dictation and meeting transcription app for macOS built in Swift/SwiftUI.

## What We Are Building

Useful Keyboard is a universal input layer for the Apple ecosystem.
Voice in, structured text out. AI formatting pass via local Ollama.
iCloud sync between Mac and iOS. Part of the Useful Ventures product suite.

## Repo Structure

```
native/MuesliNative/
├── Package.swift                    # SPM manifest (dependencies, targets)
├── Sources/
│   ├── MuesliNativeApp/             # Main app target (SwiftUI views, app entry)
│   │   ├── main.swift               # App entry point
│   │   ├── AppDelegate.swift        # NSApplicationDelegate
│   │   ├── AppIdentity.swift        # Branding strings (reads from Info.plist, fallback "Muesli")
│   │   ├── AppState.swift           # Global app state
│   │   ├── ConfigStore.swift        # UserDefaults-backed settings
│   │   ├── PasteController.swift    # Pastes transcript at cursor (NSPasteboard + Cmd+V)
│   │   ├── FloatingIndicatorController.swift  # Draggable pill during recording
│   │   ├── StreamingDictationController.swift # Orchestrates dictation pipeline
│   │   ├── StreamingMicRecorder.swift         # Audio capture via AVAudioEngine
│   │   ├── MicrophoneRecorder.swift           # Mic recording
│   │   ├── SystemAudioRecorder.swift          # ScreenCaptureKit for meeting audio
│   │   ├── FillerWordFilter.swift             # Removes uh/um
│   │   ├── CustomWordMatcher.swift            # Jaro-Winkler fuzzy matching
│   │   ├── HotkeyMonitor.swift                # Global hotkey detection
│   │   ├── MeetingSession.swift               # Chunked meeting transcription
│   │   ├── MeetingSummaryClient.swift         # AI meeting notes
│   │   ├── SettingsView.swift                 # Settings UI
│   │   ├── AboutView.swift                    # About page
│   │   ├── OnboardingView.swift               # Onboarding flow
│   │   └── ... (60+ Swift files total)
│   ├── MuesliCore/                  # Shared library target
│   │   ├── MuesliPaths.swift        # File system paths
│   │   ├── DictationStore.swift     # SQLite storage for dictations
│   │   └── StorageModels.swift      # Data models for storage
│   └── MuesliCLI/                   # CLI target
│       └── main.swift               # muesli-cli entry point
└── Tests/
    └── MuesliTests/                 # Unit tests (Swift Testing framework, @Test/@Suite)
```

The build script is `scripts/build_native_app.sh`.
It generates Info.plist at build time from environment variables.

Bundle ID: ai.useful.keyboard (set via MUESLI_BUNDLE_ID env var)

### Build Script Environment Variables

The build script supports these env vars for branding:
- `MUESLI_APP_NAME` — CFBundleName (default: "Muesli")
- `MUESLI_DISPLAY_NAME` — CFBundleDisplayName (default: same as APP_NAME)
- `MUESLI_BUNDLE_ID` — CFBundleIdentifier (default: "com.muesli.app")
- `MUESLI_APP_BUNDLE_NAME` — .app bundle name (default: "Muesli.app")
- `MUESLI_EXECUTABLE_NAME` — executable name inside bundle (default: "Muesli")
- `MUESLI_SUPPORT_DIR_NAME` — Application Support subdirectory name
- `MUESLI_SKIP_SIGN=1` — skip code signing (useful for development)

## Rules

- Do not touch transcription or audio code unless the branch specifically requires it
- Do not add cloud dependencies or API calls to external services (except Ollama on localhost)
- Do not break the existing Muesli feature set (dictation, meeting recording, CLI)
- All Swift code should follow the existing patterns in the codebase
- Test your changes compile with: swift build --package-path native/MuesliNative
- Run tests with: swift test --package-path native/MuesliNative
- All existing tests must pass after your changes
- Tests use Swift Testing framework (@Test, @Suite, #expect), NOT XCTest

## Stack

- Language: Swift 5.9+, SwiftUI, AppKit
- Package manager: Swift Package Manager (Package.swift)
- Transcription: Parakeet TDT via FluidAudio (CoreML/Neural Engine)
- Whisper fallback: SwiftWhisper (whisper.cpp on Metal)
- Voice activity: Silero VAD via FluidAudio
- Storage: SQLite via MuesliCore (WAL mode)
- Settings: ConfigStore.swift wrapping UserDefaults
- Branding: AppIdentity.swift reads from Info.plist with fallback defaults
- Auto-updates: Sparkle framework
- Analytics: TelemetryDeck
- AI formatting: Ollama at http://localhost:11434 (Branch 2 adds this)
- Sync: CloudKit iCloud.ai.useful.keyboard (Branch 3 adds this)

## Key Architecture Notes

- `AppIdentity.swift` centralizes all branding strings — it reads from the
  Info.plist (generated at build time by the build script) with "Muesli" as fallback.
- `PasteController.swift` is where transcribed text gets pasted to cursor.
  This is the insertion point for AI formatting (Branch 2).
- `MuesliCore/DictationStore.swift` handles SQLite persistence.
  This is the hook point for CloudKit sync (Branch 3).
- `FloatingIndicatorController.swift` manages the recording pill UI.
  This is where context badges go (Branch 4).

## What NOT to Do

- Do not add any Python, Node, or non-Swift runtime dependencies
- Do not add any third-party Swift packages without explicit approval
- Do not modify Package.swift dependencies without explicit approval
- Do not change the build script behavior (but you may use its env vars)
- Do not remove any existing features
- Do not rename Swift types, classes, modules, or internal variable names
  (only user-facing strings for branding)
