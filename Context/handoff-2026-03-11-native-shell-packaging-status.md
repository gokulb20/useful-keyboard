# Context Handover — Native shell scaffold landed; packaging and distribution still need hardening

**Session Date:** 2026-03-11 20:56
**Repository:** muesli
**Branch:** main

---

## Session Objective

Stabilize the current Python/AppKit app for daily use, add explicit dictation vs meeting transcript views, improve Dock/app identity behavior, scaffold the native Swift rewrite, and set up a remote macOS build/release path.

## What Got Done
- [app.py](/Users/pranavhari/Desktop/hacks/muesli/app.py#L56) — replaced the old `rumps` app shell with a direct AppKit-driven Python shell that owns status item, dashboard, preferences, runtime state, Dock activation policy, and runtime app icon behavior.
- [ui/dashboard_window.py](/Users/pranavhari/Desktop/hacks/muesli/ui/dashboard_window.py#L63) — built a native dashboard window with tabbed `Dictations` and `Meeting Transcripts` views, stats at the top, and click-to-copy transcript rows.
- [ui/status_item.py](/Users/pranavhari/Desktop/hacks/muesli/ui/status_item.py#L24) — added `Recent Dictations`, `Meeting Transcripts`, backend switching, settings, and meeting controls to the menu bar app menu.
- [dictation/hotkey.py](/Users/pranavhari/Desktop/hacks/muesli/dictation/hotkey.py#L6) — kept the staged dictation timing (`150ms` prepare / `250ms` start), added Quartz event-access preflight/request, and made listener startup fail loudly if `pynput` cannot come up.
- [storage/local_db.py](/Users/pranavhari/Desktop/hacks/muesli/storage/local_db.py#L38) — expanded SQLite to persist `dictations` and `meetings` with `word_count`, unified recent activity, and cleanup helpers.
- [storage/stats.py](/Users/pranavhari/Desktop/hacks/muesli/storage/stats.py#L34) — added dictation/meeting stats queries for total words, WPM, streaks, sessions, and meeting counts.
- [transcribe/backends.py](/Users/pranavhari/Desktop/hacks/muesli/transcribe/backends.py#L1) + [transcribe/engine.py](/Users/pranavhari/Desktop/hacks/muesli/transcribe/engine.py#L1) — refactored STT into backend-swappable Whisper/Qwen support.
- [bridge/worker.py](/Users/pranavhari/Desktop/hacks/muesli/bridge/worker.py#L1) — added a JSON-over-stdin/stdout Python worker for the future Swift/AppKit shell.
- [native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift](/Users/pranavhari/Desktop/hacks/muesli/native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift#L1) — added the first native Swift/AppKit shell scaffold, even though it is not currently buildable on this machine.
- [setup.py](/Users/pranavhari/Desktop/hacks/muesli/setup.py#L1) + [release-macos-app.yml](/Users/pranavhari/Desktop/hacks/muesli/.github/workflows/release-macos-app.yml#L1) — added `py2app` packaging plus a GitHub Actions macOS build workflow that archives `Muesli.app` and uploads it to GitHub Releases.
- [assets/muesli_app_icon.png](/Users/pranavhari/Desktop/hacks/muesli/assets/muesli_app_icon.png) + [assets/menu_m_template.png](/Users/pranavhari/Desktop/hacks/muesli/assets/menu_m_template.png) — added the green app icon and monochrome status-bar icon family.

## What Didn't Work
- **Native Swift build on local machine**: direct `swiftc` / SwiftPM AppKit compile attempts → failed before reaching Muesli code → local Apple Command Line Tools installation has a broken `SwiftBridging` / `AppKit` module-map state. Installing full Xcode or reinstalling CLT is still needed before the native Swift shell can be compiled locally.
- **Fully standalone `py2app` bundle**: rebuilt `dist/Muesli.app` several times → hit missing `libffi.8.dylib`, then `jaraco.text`, then `sounddevice` / PortAudio bundling issues → the local fully frozen bundle is still not proven distributable.
- **GitHub Packages as app distribution target**: considered as a place to publish the app → rejected because macOS `.app` bundles should be distributed as zipped release assets, not package-registry artifacts.

## Key Decisions
- **Decision**: Keep Python as the working app path while scaffolding the native Swift rewrite in parallel.
  - **Context**: The user still needed a working app immediately, but PyObjC menu/action instability had already shown up.
  - **Rationale**: This preserved a usable product while still moving toward a native shell architecture.
  - **Alternatives rejected**: Stop feature work and do a full native rewrite first.

- **Decision**: Use tabbed `Dictations` and `Meeting Transcripts` sections in the Python dashboard.
  - **Context**: The user wanted the main dashboard to mirror the native tab-switching feel of the preferences window.
  - **Rationale**: It simplified the dashboard and made the transcript split explicit without needing a larger redesign.
  - **Alternatives rejected**: Keep a single mixed activity feed as the primary transcript surface.

- **Decision**: Make Muesli Dock-visible only while windows are open.
  - **Context**: The user wanted Maccy-style menu-bar behavior plus a real app presence when `Open Muesli` is used.
  - **Rationale**: Dynamic activation (`Accessory` when idle, `Regular` while windows are visible) combines both behaviors cleanly.
  - **Alternatives rejected**: Always hide from Dock; always show in Dock.

- **Decision**: Add a GitHub Actions macOS release workflow targeting GitHub Releases.
  - **Context**: The user wanted the app pushed remotely and “published”.
  - **Rationale**: Releases are the correct downloadable surface for zipped `.app` bundles; Packages is not.
  - **Alternatives rejected**: Upload the local alias-mode app as if it were production-ready; use GitHub Packages as the primary installer surface.

## Lessons Learned
- TCC permissions for rebuilt local `.app` bundles are flaky unless the bundle identity and install path are stable.
- `pynput` hotkey handling can look like a permission problem even when the deeper issue is app identity churn.
- A packaged `.app` can have the right icon and process name while still failing on bundled native dependencies; process identity and distributability are separate problems.
- `py2app` on a dependency-heavy ML/audio app needs explicit post-processing and likely more package-data tuning than a plain Python utility.

## Nuances & Edge Cases
- The current repo state is clean after commit `e377d84` and push to `origin/main`.
- The last known working packaged path for identity testing was `dist/Muesli.app` built in alias mode (`py2app -A`), not the fully standalone frozen bundle.
- The standalone `py2app` path still needs work around `_sounddevice_data/portaudio-binaries/libportaudio.dylib` and `libffi.8.dylib`.
- The Python dashboard currently copies transcripts on row selection, not just double-click.
- Meetings are stored in SQLite at `~/Library/Application Support/Muesli/muesli.db`; transcripts are in `raw_transcript`, not exported text files.
- Qwen is available and working as a backend option, but the default deployment assumption is still Whisper unless switched in config/UI.

## Codebase Map (Files Touched)

### Modified
- [app.py](/Users/pranavhari/Desktop/hacks/muesli/app.py) — central AppKit shell, backend selection, Dock behavior, dashboard/preferences opening, hotkey startup, clipboard copy.
- [dictation/hotkey.py](/Users/pranavhari/Desktop/hacks/muesli/dictation/hotkey.py) — staged hold-to-talk logic plus Quartz event-access preflight.
- [storage/local_db.py](/Users/pranavhari/Desktop/hacks/muesli/storage/local_db.py) — DB migrations, dictation/meeting persistence, unified history.
- [setup.py](/Users/pranavhari/Desktop/hacks/muesli/setup.py) — `py2app` config and bundled asset list.
- [requirements-no-torch.txt](/Users/pranavhari/Desktop/hacks/muesli/requirements-no-torch.txt) — runtime deps, including the no-torch path and STT stack changes.
- [requirements-no-torch-dev.txt](/Users/pranavhari/Desktop/hacks/muesli/requirements-no-torch-dev.txt) — dev/test/packaging deps.

### Read / Referenced
- [audio/mic_capture.py](/Users/pranavhari/Desktop/hacks/muesli/audio/mic_capture.py) — current `sounddevice`/PortAudio-based mic path; important for packaging failures.
- [audio/system_capture.py](/Users/pranavhari/Desktop/hacks/muesli/audio/system_capture.py) — ScreenCaptureKit meeting path; not the current packaging blocker, but relevant for future native work.
- [meeting/session.py](/Users/pranavhari/Desktop/hacks/muesli/meeting/session.py) — meeting save/orchestration path.
- [config.py](/Users/pranavhari/Desktop/hacks/muesli/config.py) — current config defaults and persisted app settings.

### Related (Not Touched)
- [native/system_audio.swift](/Users/pranavhari/Desktop/hacks/muesli/native/system_audio.swift) — legacy Swift experiment worth mining later for native meeting/system-audio work.
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — direct Swift build path, currently blocked by the local Apple toolchain issue.
- [Context/handoff-summary-2026-03-08-120000.md](/Users/pranavhari/Desktop/hacks/muesli/Context/handoff-summary-2026-03-08-120000.md) — prior product/history handoff.

## Next Steps
1. **Make standalone `py2app` builds actually self-contained** — explicitly bundle `_sounddevice_data` / PortAudio and any remaining dylibs, then test a clean-machine launch path.
2. **Run the first GitHub macOS release workflow** — trigger [release-macos-app.yml](/Users/pranavhari/Desktop/hacks/muesli/.github/workflows/release-macos-app.yml), inspect the artifact, and verify whether the runner-produced bundle avoids the local packaging issues.
3. **Stabilize packaged-app permissions** — use one stable install location such as `/Applications/Muesli.app` for dogfooding; stop alternating between raw Python and rebuilt `dist/` paths when testing hotkeys.
4. **Repair local Apple toolchain** — install full Xcode or reinstall Command Line Tools, then retry [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) to resume the native Swift shell work.
5. **Decide whether to keep iterating the Python/AppKit shell** — it is usable now, but every additional UI feature invested there should be weighed against the native rewrite.

## Open Questions
- Should the next release target be a zipped `.app` only, or should the repo also generate a `.dmg` once the standalone bundle is stable?
- Does the user want the Python/AppKit dashboard polished further, or should effort shift almost entirely to the native Swift shell once the toolchain is fixed?
- Is `sounddevice` the long-term mic capture path, or should the app move to a more native audio stack to simplify packaging and reduce permission/runtime weirdness?
