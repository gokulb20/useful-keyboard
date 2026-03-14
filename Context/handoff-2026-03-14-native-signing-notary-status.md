# Context Handover — Native app now uses Developer ID signing, but notarization still fails on release-hardening issues

**Session Date:** 2026-03-14 11:26
**Repository:** muesli
**Branch:** coreml-swift

---

## Session Objective

Stabilize the installed native app path, switch builds from ad-hoc signing to the real Developer ID identity, set up notarization tooling, and improve the native floating indicator motion.

## What Got Done
- [scripts/build_native_app.sh:14](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh#L14) — default signing identity now uses `Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)` instead of ad-hoc signing.
- [scripts/build_native_app.sh:107](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh#L107) — signing now fails loudly if the configured identity is missing, rather than silently swallowing signing errors.
- [scripts/build_native_app.sh:109](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh#L109) — staged `dist-native/Muesli.app` is removed after install so `/Applications/Muesli.app` is the only real launch target.
- [scripts/store_notary_profile.sh:1](/Users/pranavhari/Desktop/hacks/muesli/scripts/store_notary_profile.sh#L1) — added helper to store a `notarytool` keychain profile.
- [scripts/notarize_app.sh:1](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh#L1) — added end-to-end notarization flow: zip app, submit with `notarytool`, staple, validate, and run `spctl`.
- [native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift:47](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift#L47) — hover and state transitions now animate with easing instead of instant frame/color jumps.
- [native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift:89](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift#L89) — added delayed hover-exit verification to stop the hover “seizure loop” caused by tracking-area churn during animated resize.
- [native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClient.swift:18](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClient.swift#L18) — fixed compile break by making missing `pythonExecutable` / `workerScript` an explicit runtime error instead of implicitly assuming non-optional URLs.
- `/Applications/Muesli.app` was rebuilt and reinstalled repeatedly from the same stable path. Current signature verification succeeded and shows:
  - `Authority=Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)`
  - `TeamIdentifier=58W55QJ567`
- Notary credentials were stored successfully in Keychain under profile:
  - `MuesliNotary`

## What Didn't Work
- **Notarization**: `./scripts/notarize_app.sh` uploaded the signed app successfully, but Apple returned `Invalid` → stapling failed because no ticket was issued → the current release build is not notarization-ready.
- **Status bar reliability**: the floating indicator can be alive while the menu bar item is still missing → this still points to intermittent status-item surfacing issues in the native shell, not a dead app process.
- **Repeated permission confusion**: before stabilizing on `/Applications/Muesli.app`, multiple bundle paths with the same bundle ID caused misleading Accessibility/Input Monitoring behavior. Deleting old `dist`/staged app copies reduced this a lot, but this history matters when debugging “why did permissions stop working?”

## Key Decisions
- **Decision**: `/Applications/Muesli.app` is the only canonical native app path.
  - **Context**: duplicate bundle paths (`dist`, `dist-native`, `/Applications`) were confusing TCC and launch behavior.
  - **Rationale**: same install path + same bundle ID + same signing identity is the minimum viable stable app identity.
  - **Alternatives rejected**: continuing to test from staged build folders.

- **Decision**: use the real Developer ID certificate immediately for local dogfooding builds.
  - **Context**: ad-hoc signing was still causing trust/TCC drift even after moving to `/Applications`.
  - **Rationale**: this gets the local install path closer to real distributed behavior and should reduce repeated permission prompts.
  - **Alternatives rejected**: staying on ad-hoc signing until “later”.

- **Decision**: set up notarization now even though the app is still in active development.
  - **Context**: user asked whether to wait; recommendation was to wire the flow now and use it for milestone builds.
  - **Rationale**: surfacing notarization blockers early is better than discovering them only at distribution time.
  - **Alternatives rejected**: postponing all notarization work until the app is “complete”.

## Lessons Learned
- Stable bundle ID and stable `/Applications` install path are necessary but not sufficient; TCC stability also depends on stable signing identity.
- Developer ID signing helped, but notarization has stricter requirements than ordinary signing.
- Nested executables like `MuesliSystemAudio` must be signed correctly too; notarization inspects them independently.
- `com.apple.security.get-task-allow` is a debug entitlement and blocks notarized distribution.
- Hover animations that resize tracking-area-backed views need delayed exit verification or they can oscillate badly.

## Nuances & Edge Cases
- Current signing identity in the keychain:
  - `Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)`
- Current notary profile in keychain:
  - `MuesliNotary`
- Current notarization submission ID:
  - `cbeb314f-fe96-4ca5-91cc-9c238a8170f1`
- Current notarization result:
  - `status=Invalid`
  - `statusSummary=Archive contains critical validation errors`
- Apple’s exact rejection reasons from the fetched notary log:
  - `Muesli.app/Contents/MacOS/Muesli` does not have hardened runtime enabled
  - `Muesli.app/Contents/Resources/MuesliSystemAudio` is not signed with a valid Developer ID certificate
  - `MuesliSystemAudio` signature does not include a secure timestamp
  - `MuesliSystemAudio` does not have hardened runtime enabled
  - `MuesliSystemAudio` requests `com.apple.security.get-task-allow`
- Gatekeeper check before notarization:
  - `spctl -a -vv /Applications/Muesli.app` reported `source=Unnotarized Developer ID`
- Build still emits warnings that should be cleaned up later:
  - main-actor mutation warning for `lastExternalApp` in [MuesliController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift)
  - deprecated `activateIgnoringOtherApps` use in [PreferencesWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/PreferencesWindowController.swift) and [RecentHistoryWindowController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift)

## Codebase Map (Files Touched)

### Modified
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — switched to real Developer ID signing by default, validates identity, installs only to `/Applications`.
- [native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift) — eased motion, smoother state transitions, fixed hover-loop behavior.
- [native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClient.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClient.swift) — compile/runtime guard for missing bundled Python worker paths.

### Added
- [scripts/store_notary_profile.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/store_notary_profile.sh) — stores `notarytool` credentials using Apple ID + app-specific password + team ID.
- [scripts/notarize_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh) — current notarization entrypoint for installed `/Applications/Muesli.app`.

### Read / Referenced
- [native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift) — verifies app icon setup and native controller launch path.
- [native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift) — status item is still constructed normally despite intermittent missing-menu-bar symptoms.
- Apple notary log for submission `cbeb314f-fe96-4ca5-91cc-9c238a8170f1` — source of exact notarization blockers.

### Related (Not Touched)
- [native/MuesliNative/Sources/MuesliSystemAudio/main.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliSystemAudio/main.swift) — likely source of the nested-binary signing/notarization problems and the place to inspect for `get-task-allow` / release build settings.
- [native/MuesliNative/Package.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Package.swift) — likely where release configuration and product layout will need adjustment for hardened-runtime-ready notarization.
- [Context/handoff-2026-03-13-notarization-failure-report.md](/Users/pranavhari/Desktop/hacks/muesli/Context/handoff-2026-03-13-notarization-failure-report.md) — previous focused note containing the first notarization rejection details.

## Next Steps
1. **Make release signing notarization-ready** — update [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) to sign with hardened runtime (`--options runtime`) and secure timestamps, and sign nested binaries explicitly before signing the app bundle.
2. **Fix `MuesliSystemAudio` release entitlements** — remove `com.apple.security.get-task-allow` from the release path and confirm it is signed with the same Developer ID identity as the main app.
3. **Retry notarization after release-hardening fixes** — rerun [scripts/notarize_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh), then validate with:
   - `xcrun stapler validate /Applications/Muesli.app`
   - `spctl -a -vv /Applications/Muesli.app`
4. **Keep testing only from `/Applications/Muesli.app`** — do not reintroduce staged bundle testing for normal dogfooding.
5. **Clean remaining Swift warnings** — especially the actor isolation warning in `MuesliController.swift`, because it will become an error under stricter Swift 6 mode.

## Open Questions
- What is the cleanest way to produce a release-style `MuesliSystemAudio` binary without `get-task-allow` from the current SwiftPM-based build?
- Should hardened runtime be applied uniformly to all native helper binaries now, or only when building a dedicated release profile?
- Is the remaining missing-status-bar-icon behavior purely AppKit/status-item flakiness, or still partly an install/cache issue on this machine?
