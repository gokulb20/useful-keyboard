# Context Handover — Native Muesli app is usable locally; signing/distribution remains the main blocker

**Session Date:** 2026-03-13 01:00
**Repository:** muesli
**Branch:** main

---

## Session Objective

Stabilize the native Swift/AppKit build as the primary local app path, reduce macOS permission confusion, add missing native parity/features, and record the current Apple Developer signing/distribution state for the next agent.

## What Got Done
- [native/MuesliNative/Sources/MuesliNativeApp/HotkeyMonitor.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/HotkeyMonitor.swift) — native hotkey path is working from the installed app after permissions were re-granted to the correct bundle.
- [native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift) — hover expansion and centered active-state pill layout were brought closer to the Python version.
- [native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift) — dashboard reflects the Python path more closely with split transcript views and copy-on-row-click behavior.
- [native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift) — added `Meeting Transcripts`, `Transcription Backend`, and new `Meetings Backend` submenus.
- [meeting/summary.py](/Users/pranavhari/Desktop/hacks/muesli/meeting/summary.py) — meeting summaries can now route via `OpenAI` or `OpenRouter` using config-driven selection.
- [config.py](/Users/pranavhari/Desktop/hacks/muesli/config.py) and [native/MuesliNative/Sources/MuesliNativeApp/Models.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/Models.swift) — added shared `meeting_summary_backend` config support.
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — build/install flow targets `/Applications/Muesli.app` and now deletes the staged `dist-native/Muesli.app` copy after install to avoid bundle-path confusion.
- [assets/muesli_app_icon.png](/Users/pranavhari/Desktop/hacks/muesli/assets/muesli_app_icon.png) and [assets/muesli.icns](/Users/pranavhari/Desktop/hacks/muesli/assets/muesli.icns) — icon was recentered/scaled to a more standard macOS footprint and rebuilt into the app bundle.
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — current installed bundle path is `/Applications/Muesli.app`; user manually deleted the old `dist/` py2app bundle to eliminate duplicate `com.muesli.app` identities.

## What Didn't Work
- **Testing multiple app bundles with the same bundle ID**: `dist/Muesli.app`, `dist-native/Muesli.app`, and `/Applications/Muesli.app` were all in play at different points → TCC/hotkey/paste behavior became flaky and misleading → keep exactly one canonical installed app path (`/Applications/Muesli.app`) for real testing.
- **Assuming stable path + bundle ID were enough for TCC stability**: moving to `/Applications` helped, but ad-hoc signing still caused permission drift after rebuilds → the missing piece is proper Developer ID signing.
- **Native paste variations with extra focus/app-reactivation logic**: these regressed behavior and were rolled back/simplified multiple times → keep paste logic minimal and treat Accessibility/TCC as the real gating factor.

## Key Decisions
- **Decision**: `/Applications/Muesli.app` is the only canonical app path for native testing.
  - **Context**: duplicate app bundles with the same `com.muesli.app` identity were confusing both the user and macOS permissions.
  - **Rationale**: a single install path is the minimum needed for sane TCC behavior.
  - **Alternatives rejected**: continuing to launch from `dist/` or `dist-native/`.

- **Decision**: keep the native app as the main path, but keep Python only for STT/model execution for now.
  - **Context**: PyObjC UI/action dispatch had been unstable, but the STT stack in Python already works.
  - **Rationale**: Swift/AppKit owns the shell; Python remains the practical model/inference runtime until or unless inference is ported.
  - **Alternatives rejected**: reverting to the Python shell as the long-term main app.

- **Decision**: add a separate `Meetings Backend` selector rather than overloading the transcription backend selector.
  - **Context**: STT backend choice and meeting-summary LLM provider choice are different concerns.
  - **Rationale**: explicit separation matches the actual architecture and user intent.
  - **Alternatives rejected**: implicitly tying meeting summaries to the dictation/STT backend.

- **Decision**: capture only relevant Apple Developer signing state in handoff, not the pricing/doubt discussion.
  - **Context**: user explicitly asked to omit tactical discussion about paying less.
  - **Rationale**: next agent needs the technical distribution/signing facts only.
  - **Alternatives rejected**: carrying over negotiation/pricing speculation.

## Lessons Learned
- Stable install path and bundle ID are necessary but not sufficient for macOS permissions; TCC also keys off the app’s signing identity.
- Rebuilding ad-hoc signed apps in place can still make permissions feel inconsistent, even when the bundle ID does not change.
- When hotkey works but paste does not, `Accessibility` is the first permission to suspect; `Input Monitoring` mainly affects the listener path.
- Duplicate bundles with the same bundle ID are toxic for debugging macOS app behavior.

## Nuances & Edge Cases
- Current native app is installed at `/Applications/Muesli.app` and is still **adhoc signed**. `codesign -dv --verbose=4 /Applications/Muesli.app` showed:
  - `Identifier=com.muesli.app`
  - `Signature=adhoc`
  - `TeamIdentifier=not set`
- User has installed full Xcode and the Xcode license / first launch setup is complete; this unblocked native AppKit compilation locally.
- The build still emits warnings:
  - `lastExternalApp` main-actor mutation from a sendable closure in [MuesliController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift)
  - deprecated `activateIgnoringOtherApps` usage in [PreferencesWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/PreferencesWindowController.swift) and [RecentHistoryWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift)
- The meeting summary system prompt is still the structured note prompt in [meeting/summary.py](/Users/pranavhari/Desktop/hacks/muesli/meeting/summary.py); only the backend/provider selection changed.

## Codebase Map (Files Touched)

### Modified
- [config.py](/Users/pranavhari/Desktop/hacks/muesli/config.py) — added `meeting_summary_backend` default.
- [meeting/summary.py](/Users/pranavhari/Desktop/hacks/muesli/meeting/summary.py) — supports `openai` vs `openrouter` meeting summary routing and API-key/model lookup.
- [native/MuesliNative/Sources/MuesliNativeApp/Models.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/Models.swift) — added `MeetingSummaryBackendOption` and persisted config field.
- [native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift) — meeting-backend selection wiring and native controller parity work.
- [native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift) — added `Meetings Backend` submenu.
- [native/MuesliNative/Sources/MuesliNativeApp/PasteController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/PasteController.swift) — native paste path was simplified again after regressions.
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — installs to `/Applications/Muesli.app`, then removes staged `dist-native` bundle.
- [assets/muesli_app_icon.png](/Users/pranavhari/Desktop/hacks/muesli/assets/muesli_app_icon.png) — normalized icon bounds/canvas usage.
- [assets/muesli.icns](/Users/pranavhari/Desktop/hacks/muesli/assets/muesli.icns) — regenerated from normalized PNG.

### Read / Referenced
- [meeting/session.py](/Users/pranavhari/Desktop/hacks/muesli/meeting/session.py) — confirms meeting summaries are generated through `summarize_transcript(...)`.
- [native/MuesliNative/Sources/MuesliNativeApp/ConfigStore.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/ConfigStore.swift) — native config persistence path.
- [native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift) — current native dashboard behavior and warnings context.
- [native/MuesliNative/Sources/MuesliNativeApp/PreferencesWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/PreferencesWindowController.swift) — deprecation warning and settings UI context.

### Related (Not Touched)
- [bridge/worker.py](/Users/pranavhari/Desktop/hacks/muesli/bridge/worker.py) — still the Python STT worker behind the native shell.
- [scripts/postprocess_py2app_bundle.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/postprocess_py2app_bundle.sh) — older py2app path still exists in repo, but should not be used for primary native testing.
- [release-macos-app.yml](/Users/pranavhari/Desktop/hacks/muesli/.github/workflows/release-macos-app.yml) — CI packaging pipeline exists, but proper signing/notarization is still outstanding.

## Next Steps
1. **Get a real Developer ID signing identity into the login keychain** — once Apple Developer enrollment is fully confirmed, create/install a `Developer ID Application` certificate and switch the build to use it instead of ad-hoc signing.
2. **Update the native build script to use the real signing identity automatically** — remove the ad-hoc default once a valid identity exists and fail loudly on signing errors.
3. **Retest TCC stability after real signing** — verify that `Accessibility` and `Input Monitoring` stop requiring repeated removal/re-addition after rebuild/install.
4. **Address the Swift warnings that will become future errors** — fix `lastExternalApp` actor isolation and replace deprecated activation APIs.
5. **Verify meeting summary provider switching end-to-end** — run one meeting summary with `OpenAI` and one with `OpenRouter` and confirm the expected provider/model is used.

## Open Questions
- Once the Apple Developer account finishes processing, what exact signing identity name will appear in Keychain for the build script to target?
- Should the native app eventually expose meeting-summary provider selection in Preferences as well, or is the status-menu selector enough?
- Is the current native paste path now reliable enough across multiple target apps, or does it still need one more round of hardening after real signing?
