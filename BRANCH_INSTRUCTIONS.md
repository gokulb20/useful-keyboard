# Branch: feature/branding

Read AGENTS.md first for repo context.

## Goal

Rebrand the app from "Muesli" to "Useful Keyboard" and apply a strict minimal design language: black background, white text, no emojis, simple or no icons, very minimal, natural navigation.

## Design Language

- **Background**: Pure black (#000000) or near-black (#0A0A0A). The current theme uses #111214 — make it darker.
- **Text**: White at 90%+ opacity for primary, 60% for secondary, 35% for tertiary. No colored text except for interactive elements.
- **Accent**: Keep the blue accent (#6BA3F7 dark mode) but use it sparingly — only for active selections and interactive controls.
- **No emojis**: The codebase currently has no emoji in UI strings (good). Keep it that way. Remove any emoji-like SF Symbols if they feel decorative.
- **Icons**: Use SF Symbols only where they serve a functional purpose (e.g., mic icon when recording). Remove decorative icons. The sidebar nav items can be text-only if it looks cleaner.
- **Typography**: Keep the Inter font (AppFonts.swift). Clean, sans-serif, minimal.
- **Spacing**: Keep the existing 4pt grid from MuesliTheme.

## Specific Tasks

### 1. Rename User-Facing Strings

These are the exact locations where "Muesli" appears in user-facing text:

| File | Line | Current String | Change To |
|---|---|---|---|
| `Sources/MuesliNativeApp/AppIdentity.swift` | 5 | `private static let defaultName = "Muesli"` | `"Useful Keyboard"` |
| `Sources/MuesliNativeApp/OnboardingView.swift` | 164 | `"Welcome to Muesli"` | `"Welcome to Useful Keyboard"` |
| `Sources/MuesliNativeApp/OnboardingView.swift` | 277 | `"Muesli needs a few macOS permissions to work properly..."` | `"Useful Keyboard needs a few macOS permissions to work properly..."` |
| `Sources/MuesliNativeApp/OnboardingWindowController.swift` | 34 | `window.title = "Welcome to Muesli"` | `"Welcome to Useful Keyboard"` |
| `Sources/MuesliNativeApp/SidebarView.swift` | 78 | `"muesli"` (sidebar logo text) | `"useful keyboard"` or just `"keyboard"` |
| `Sources/MuesliNativeApp/StatusBarController.swift` | 51 | Uses `AppIdentity.displayName` | Already dynamic, will update via AppIdentity |

Also grep for any other user-facing "Muesli" or "muesli" strings across all `.swift` files in `Sources/MuesliNativeApp/`. Only change user-facing strings (UI labels, window titles, alert text, onboarding copy). Do NOT rename Swift types, module names, variable names, or internal identifiers.

### 2. Update Build Script Bundle ID

The build script `scripts/build_native_app.sh` generates Info.plist at build time using env vars. The defaults are hardcoded in the script:

| Variable | Current Default | Change To |
|---|---|---|
| `APP_NAME` (line ~12) | `Muesli` | `Useful Keyboard` |
| `APP_DISPLAY_NAME` (line ~13) | `$APP_NAME` | Keep as-is (inherits) |
| `APP_BUNDLE_NAME` (line ~14) | `$APP_NAME.app` | Keep as-is (becomes `Useful Keyboard.app`) |
| `APP_EXECUTABLE_NAME` (line ~15) | `Muesli` | `Useful Keyboard` |
| `BUNDLE_ID` (line ~17) | `com.muesli.app` | `ai.useful.keyboard` |

The script uses env var overrides (`MUESLI_APP_NAME`, `MUESLI_BUNDLE_ID`, etc.) — change the defaults in the script itself so it works without env vars.

### 3. Update Theme Colors (MuesliTheme.swift)

File: `Sources/MuesliNativeApp/MuesliTheme.swift`

Make the dark mode deeper/blacker:

| Token | Current Value | New Value |
|---|---|---|
| `backgroundDeep` (dark) | `0x111214` | `0x000000` or `0x050505` |
| `backgroundBase` (dark) | `0x161719` | `0x0A0A0A` |
| `backgroundRaised` (dark) | `0x1C1D20` | `0x111111` |
| `backgroundHover` (dark) | `0x232528` | `0x1A1A1A` |
| `surfacePrimary` (dark) | `0x262830` | `0x1E1E1E` |
| `surfaceSelected` (dark) | `0x2E3340` | `0x252525` |

Keep the text opacity levels as they are (92%, 62%, 40% white). Keep the accent blue.

Remove light mode support or keep it but don't optimize for it — this app is dark-mode-only per the user's design intent.

### 4. Simplify the Sidebar (SidebarView.swift)

Current sidebar has these items with SF Symbol icons:
- Dictations (mic.fill)
- Meetings (person.2.fill) with folder tree
- Dictionary (character.book.closed)
- Models (square.and.arrow.down)
- Shortcuts (keyboard)
- Settings (gearshape)
- About (info.circle)

Changes:
- Replace the MWaveformIcon logo (22x22) with simple text: "useful keyboard" in the theme's title font, white, no icon
- Consider removing SF Symbol icons from nav items and using text-only labels. If icons are kept, use the simplest possible SF Symbols.
- The greeting "Hi, {name}" below the logo can stay — it's a nice personal touch
- Navigation should feel like a clean list, not a toolbar

### 5. Simplify Onboarding (OnboardingView.swift)

Current onboarding has 5 steps with the MWaveformIcon (80x48).

Changes:
- Replace MWaveformIcon with simple text: "Useful Keyboard" in large bold white text
- Keep the 5 steps but make them feel cleaner
- Step 1 subtitle: change `"Local-first dictation and meeting transcription for macOS"` to something like `"Voice in, text out."` or keep it but make it concise
- Remove any decorative elements
- Keep the dark background (#000000 or near-black)

### 6. Update Menu Bar Icon

Current: `assets/menu_m_template.png` (an M-shaped waveform)

Create a simple replacement:
- A minimal "K" letterform or a simple microphone silhouette as a template image
- Must be a template image (white on transparent, macOS inverts for light menu bars)
- 18x18 logical pixels, provide @1x and @2x versions
- Name: `menu_icon_template.png` and `menu_icon_template@2x.png`

Update `RuntimePaths.swift` (lines 14-15) to reference the new filename.
Update `scripts/build_native_app.sh` to copy the new icon file (currently copies `menu_m_template.png`).

### 7. App Icon

Current: `assets/muesli.icns` and `assets/muesli_app_icon.png`

Create a minimal placeholder:
- Black rounded square with "UK" in white, centered
- Or a simple white keyboard/microphone glyph on black
- Generate as `useful_keyboard.icns` and `useful_keyboard_app_icon.png`
- Update the build script's `CFBundleIconFile` reference and the `cp` command for the icon

### 8. Remove MWaveformIcon Usage

File: `Sources/MuesliNativeApp/MWaveformIcon.swift`

This is the custom "M" logo component. After replacing its usage in SidebarView and OnboardingView with text, you can either:
- Delete the file entirely if nothing references it
- Or keep it for the floating indicator waveform (check if FloatingIndicatorController uses it)

Note: FloatingIndicatorController.swift has its own waveform rendering (CALayer bars, not MWaveformIcon). So MWaveformIcon may be safe to remove entirely.

### 9. StatsHeaderView.swift Simplification

Current: 4 stat cards with colored SF Symbol icons (flame.fill orange, character.cursor.ibeam blue, gauge green, person.2.fill blue)

Changes:
- Remove colored icons or make them white/gray
- Keep the stat numbers and labels
- Make it feel like a clean data dashboard, not gamified

## Files NOT to Touch

- Anything in `Sources/MuesliCore/` (storage layer)
- `Sources/MuesliCLI/` (CLI stays as muesli-cli)
- Audio/transcription files: StreamingMicRecorder, MicrophoneRecorder, SystemAudioRecorder, FluidAudioBackend, WhisperCppBackend, NemotronStreamingBackend, TranscriptionRuntime, FillerWordFilter, CustomWordMatcher
- Meeting logic: MeetingSession, MeetingDetector, MeetingSummaryClient, CalendarMonitor
- PasteController.swift, HotkeyMonitor.swift, StreamingDictationController.swift
- Package.swift (no dependency changes)

## Verification

```bash
swift build --package-path native/MuesliNative
swift test --package-path native/MuesliNative
```

Both must pass. Do not modify any test files unless a test explicitly asserts on the string "Muesli" in a user-facing context (update those to "Useful Keyboard").
