# Context Handover — Native Swift runtime landed; meetings UI narrowed to Notes-style polish

**Session Date:** 2026-03-14 18:20
**Repository:** muesli
**Branch:** coreml-swift

---

## Session Objective

Capture the current state of the native Swift route and the UI polish work so the next agent can continue from the accepted product direction without rediscovering the earlier failed passes.

## What Got Done
- `native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift:8` — native app startup now registers bundled fonts before controller boot so the meetings UI can rely on Inter without assuming local system installation.
- `native/MuesliNative/Sources/MuesliNativeApp/AppFonts.swift:8` — added a small font runtime that registers bundled Inter faces from app resources or repo assets and falls back to system fonts if registration fails.
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift:139` — kept the existing dashboard shell and dictations tab intact while preserving the native history window as the main inspection surface.
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift:223` — replaced only the meetings tab with a Notes-style split view: left sidebar of recent meetings, right document pane for rendered notes/transcript actions.
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift:341` — sidebar rendering now rebuilds chronological meeting rows with compact metadata and preview text rather than the earlier calendar-heavy “Coming up” experiment.
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift:390` — meeting selection now renders a notes-first detail panel and keeps transcript access secondary.
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift:507` — notes rendering supports markdown-like styling for headings, bullets, and paragraphs so generated summaries read like documents instead of raw blobs.
- `scripts/build_native_app.sh:12` — native packaging supports a separate app identity (`muesli-native.app`) with its own bundle ID, executable name, and Application Support directory for safe side-by-side testing against the old app.
- `scripts/build_native_app.sh:48` — build now bundles `assets/fonts` into app resources so the temporary native variant is self-contained.
- `assets/fonts/Inter-Regular.ttf` — bundled Inter family into the repo/app for the UI polish pass.
- `git` — committed and pushed the accepted meetings UI pass as `5735233 Redesign native meetings view as notes workspace` on `origin/coreml-swift`.

## What Didn't Work
- **Granola-style meetings home**: an initial pass moved the whole history window toward a Granola-like upcoming-meetings dashboard → it changed too much outside the meetings scope and made the product feel stitched together → the user rejected that direction and asked to keep dictations as-is.
- **Calendar-heavy upcoming list**: the Granola-inspired meetings view surfaced all-day holidays and noisy calendar entries in the primary pane → this made the app feel wrong immediately for actual meeting review → the final pass dropped that model and centered recorded meetings instead.

## Key Decisions
- **Decision**: Keep the native Swift route on `coreml-swift` as the main experimental branch.
  - **Context**: The branch already contains the larger runtime shift away from Python hot-path transcription.
  - **Rationale**: UI polish for the native app should stay attached to the same branch as the native runtime so testing and product iteration happen on one installable target.
  - **Alternatives rejected**: Spinning the UI work into a separate branch before validating the native route.
- **Decision**: Preserve `Dictations` and redesign only `Meetings`.
  - **Context**: The first UI pass changed the entire dashboard under a Granola-inspired concept.
  - **Rationale**: The user explicitly wanted the meeting transcription section to evolve while keeping transcriptions/dictations in their previous table-based form.
  - **Alternatives rejected**: Reworking the whole history window; keeping the Granola-style “Coming up” home as the default meetings surface.
- **Decision**: Use an Apple Notes-inspired meetings workspace, not a Granola clone.
  - **Context**: Granola was useful as a product reference, but its meetings home, typography, and framing were not the right first fit.
  - **Rationale**: A simple left-sidebar/right-document structure better matches recorded meeting review and is lower-risk to polish incrementally.
  - **Alternatives rejected**: Copying Granola more literally; keeping the old tabular meetings list.
- **Decision**: Bundle Inter in-app.
  - **Context**: The user wanted Inter specifically and the temporary app should not depend on host font availability.
  - **Rationale**: Bundling keeps typography stable across local builds and packaged installs of `muesli-native.app`.
  - **Alternatives rejected**: Assuming Inter is already installed; using Granola-like serif styling; staying on system font only.
- **Decision**: Keep `muesli-native.app` separate from `Muesli.app`.
  - **Context**: The native Swift route needed side-by-side performance and permission testing against the old app.
  - **Rationale**: Separate bundle ID and support directory avoid collisions in TCC permissions, app replacement, and local data.
  - **Alternatives rejected**: Overwriting the original app bundle during native experiments.

## Lessons Learned
- Product references are useful for structure, but copying the whole frame too early creates scope errors faster than it creates clarity.
- The user’s preferred iteration shape is narrow and reversible: keep working surfaces stable and redesign only the area under discussion.
- For the meetings experience, document readability matters more than adding dashboard widgets.

## Nuances & Edge Cases
- `muesli-native.app` is treated by macOS as a separate app because it uses a different bundle ID, so microphone/input monitoring/accessibility/screen recording/calendar permissions need to be granted again during testing.
- The old Python-backed app was shut down during testing to avoid hotkey conflicts on left command; this matters when comparing dictation behavior between old and native variants.
- The native app still has a Python fallback path in the broader `coreml-swift` branch, but current testing intent is to exercise the Swift-native path first.
- The meetings UI now ignores the earlier calendar monitor work for the main surface even though calendar-related code still exists elsewhere in the branch history.

## Codebase Map (Files Touched)

### Modified
- `native/MuesliNative/Sources/MuesliNativeApp/AppDelegate.swift` — registers bundled fonts at app launch before controller startup.
- `native/MuesliNative/Sources/MuesliNativeApp/AppFonts.swift` — new helper for Inter registration and font selection with safe fallbacks.
- `native/MuesliNative/Sources/MuesliNativeApp/RecentHistoryWindowController.swift` — accepted Notes-style meetings redesign while preserving dictations.
- `scripts/build_native_app.sh` — supports the isolated `muesli-native` app identity and bundles fonts into app resources.
- `assets/fonts/Inter-Bold.ttf` — bundled UI font.
- `assets/fonts/Inter-Medium.ttf` — bundled UI font.
- `assets/fonts/Inter-Regular.ttf` — bundled UI font.
- `assets/fonts/Inter-SemiBold.ttf` — bundled UI font.

### Read / Referenced
- `Context/handoff-summary-2026-03-05-230000.md` — earlier project summary used for grounding the native-route narrative.
- `Context/handoff-2026-03-13-native-app-signing-state.md` — latest native packaging/signing context used to confirm the app-variant strategy.

### Related (Not Touched)
- `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift` — owns runtime/backend selection and is the next place to instrument native-vs-legacy performance.
- `native/MuesliNative/Sources/MuesliNativeApp/TranscriptionRuntime.swift` — native transcription runtime abstraction added on this branch; key for any deeper Core ML/WhisperKit evaluation.
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingSummaryClient.swift` — summary generation path for meetings, relevant if the detail document needs richer rendering or actions.
- `native/MuesliNative/Sources/MuesliNativeApp/PreferencesWindowController.swift` — still contains build warnings and remains a likely cleanup target.

## Next Steps
1. **Add lightweight performance instrumentation** — capture hotkey release to transcription start, transcription duration, and paste latency inside the native runtime so `muesli-native` can be compared against the old app with actual numbers.
2. **Polish the Notes-style meetings UI** — tune sidebar density, document spacing, metadata hierarchy, and empty/loading states without changing the accepted information architecture.
3. **Run a focused manual smoke test on `muesli-native.app`** — verify dictation, meeting selection, notes rendering, copy actions, and permissions on the isolated app bundle.
4. **Decide how far to push markdown rendering** — current styling is lightweight; confirm whether richer markdown support is worth implementing or whether summary text should stay constrained.
5. **Clean residual build warnings** — especially the deprecated activation call in preferences and the actor-isolation warning in the controller.

## Open Questions
- Do we want the meetings document pane to expose transcript inline beneath the notes, or keep transcript access behind a dedicated action only?
- Should the meetings sidebar eventually include upcoming calendar events again, but filtered to real meetings only, or should it stay strictly focused on recorded meetings?
- Once performance instrumentation is added, is the native Swift route fast enough to justify continuing away from the legacy Python path for all dictation flows?
