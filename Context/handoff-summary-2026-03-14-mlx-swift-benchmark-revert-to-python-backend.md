# Context Handover — MLX Swift benchmarked, reverted to Python MLX backend with SwiftUI frontend

**Session Date:** 2026-03-14 15:00–21:00
**Repository:** muesli
**Branch:** main (merged from coreml-swift)

---

## Session Objective
Integrate MLX Swift (mlx-swift-audio) as the native transcription engine replacing WhisperKit, benchmark it against Python mlx-whisper, and decide the optimal architecture. Ultimately, revert to Python MLX backend while keeping the SwiftUI dashboard UI.

## What Got Done

### Phase 1: MLX Swift Integration (later reverted)
- `native/MuesliNative/Package.swift` — Replaced WhisperKit with mlx-swift-audio dependency, added MLXBench target
- `LocalPackages/mlx-swift-audio/` — Cloned and patched DePasqualeOrg/mlx-swift-audio for Swift 6.1.2 compatibility (tools-version 6.2→5.9, excluded TTS/FunASR/Codec code, fixed `isolated deinit`)
- `LocalPackages/swift-tiktoken/` — Cloned and patched swift-tools-version 6.2→5.9
- `Sources/MuesliNativeApp/TranscriptionRuntime.swift` — Rewrote with `TranscriptionCoordinator` actor wrapping `WhisperEngine` from mlx-swift-audio
- `Sources/MuesliNativeApp/Models.swift` — Replaced `BackendOption`/`TranscriptionRuntimeOption` with `STTModelOption` enum + configurable `WhisperQuantization`
- All consuming files updated (MuesliController, MeetingSession, AppState, SettingsView, StatusBarController)
- PythonWorkerClient.swift and PythonWorkerClientAsync.swift deleted
- Build succeeded (168s with MLX deps)

### Phase 2: Benchmarking
- `benchmarks/bench_mlx.py` — Python mlx-whisper benchmark script
- `benchmarks/run_bench.sh` — Comparison runner (MLX Swift vs Python)
- `Sources/MLXBench/main.swift` — Swift MLX benchmark executable
- Benchmark results (whisper-small.en, fp16, LJ Speech 5s clip, 5 iterations):

| Metric | MLX Swift | Python mlx-whisper |
|---|---|---|
| Warm avg | **1.582s** | **0.319s** |
| App size | 98MB | 2.2MB |
| Accuracy | Hallucinations, repetitions | Clean |

### Phase 3: Revert to Python backend with SwiftUI frontend
- `Package.swift` — Zero external dependencies, just sqlite3
- `TranscriptionRuntime.swift` — Rewritten: `TranscriptionCoordinator` wraps `PythonWorkerClient` instead of `WhisperEngine`
- `PythonWorkerClient.swift` — Restored from main branch
- `PythonWorkerClientAsync.swift` — Created async wrappers
- `Models.swift` — Reverted to `BackendOption` struct, added robust `init(from:)` decoder
- `RuntimePaths.swift` — Restored Python fields (pythonExecutable, workerScript, pasteScript)
- `MuesliController.swift` — Uses `BackendOption`, `PythonWorkerClient`, `TranscriptionCoordinator`
- `build_native_app.sh` — Back to `swift build`, bundles worker.py, generates runtime.json with Python paths, adds install confirmation prompt
- All MLX artifacts deleted (LocalPackages/, MLXBench/, WhisperKitBench/, Package.resolved)
- Build: 14.8s, binary: 1.1MB
- Merged `coreml-swift` → `main`, removed Muesli-native.app

### Phase 4: Tests (partially done, then removed)
- Created test suite (42 tests) with Swift Testing framework covering Models, AppConfig, DictationStore, ConfigStore, TranscriptFormatter, TranscriptionCoordinator
- Found and fixed real bug: AppConfig `init(from:)` failed on missing keys (added custom decoder with defaults)
- Tests were removed when MLX dependency was dropped (they imported MLXAudio)

## What Didn't Work
- **MLX Swift performance**: Community port (DePasqualeOrg/mlx-swift-audio) is 5x slower than Apple's Python mlx-whisper. The gap is in the decoding loop orchestration, not the MLX GPU compute.
- **MLX Swift accuracy**: Produced hallucinations (`[BLANK_AUDIO]`), repetitions ("hello hello hello hello"), garbled text on short recordings.
- **`swift build` + Metal**: SPM's `swift build` doesn't compile Metal shaders → "Failed to load the default metallib" at runtime. Must use `xcodebuild` for MLX Swift apps.
- **`swift test` + Metal**: Same Metal library issue. MLX integration tests need `xcodebuild test-without-building`.
- **Overwrote /Applications/Muesli.app**: Installed native build over user's working Python app without asking. Had to rebuild from main via git worktree to restore.
- **runtime.json pointing to deleted worktree**: After `git worktree remove`, the bundled runtime.json still referenced `/tmp/muesli-main` paths. Python worker couldn't start.
- **Config corruption from tests**: ConfigStore/DictationStore tests wrote to the real `~/Library/Application Support/Muesli/` directory, corrupting the user's config.

## Key Decisions
- **Decision**: Use Python mlx-whisper backend, not MLX Swift
  - **Context**: Benchmarks showed 5x speed gap, accuracy issues, 98MB binary
  - **Rationale**: Apple's own optimized Python implementation vs community Swift port. Same C++ GPU engine underneath — gap is in orchestration code.
  - **Alternatives rejected**: (1) Pure Swift MLX — too slow/inaccurate. (2) Port Apple's Python mlx-whisper to Swift line-by-line — feasible (~3,339 lines) but significant effort for uncertain payoff.

- **Decision**: Keep SwiftUI dashboard from coreml-swift, merge to main
  - **Context**: coreml-swift had modern dark-theme SwiftUI dashboard; main had utilitarian AppKit UI
  - **Rationale**: The UI work is valuable regardless of backend choice

- **Decision**: Default quantization fp16, not q4
  - **Context**: Python mlx-whisper uses fp16; q4 degrades accuracy especially on small models
  - **Rationale**: Fair benchmark comparison, better transcription quality

## Lessons Learned
- `mlx-whisper` is Apple-maintained (`mlx@group.apple.com`, from `ml-explore/mlx-examples`). The Swift port is community (1 person).
- Both Python and Swift MLX bindings wrap the same C++ engine. Performance differences are in orchestration, not compute.
- Swift HuggingFace Hub cache (`~/Library/Caches/huggingface/models/`) differs from Python (`~/.cache/huggingface/hub/`). Models can't be shared between them.
- WhisperKit CoreML models cached at `~/Library/Caches/WhisperKitBench/` (540MB, cleaned up this session).
- A faithful line-by-line port of Apple's 3,339 lines of Python mlx-whisper to Swift SHOULD achieve parity — the current community port reimplemented things differently rather than translating directly.

## Nuances & Edge Cases
- **Never install native builds as Muesli.app** — use Muesli-native.app with bundle ID com.muesli.native. Memory saved at `memory/feedback_separate_app_bundles.md`.
- **Always confirm before overwriting /Applications/**. Memory saved at `memory/feedback_confirm_destructive.md`.
- Python worker's `transcribe_file` returns text only, no timestamped segments. Meeting transcription returns a single segment per audio file — TranscriptFormatter.merge() handles this.
- AppConfig uses custom `init(from:)` to handle missing keys gracefully (forward-compatible with old config files).
- The `build_native_app.sh` now uses `swift build` (not `xcodebuild`) since no Metal shaders are needed.
- HotkeyMonitor has a deliberate 150ms→250ms two-stage activation (prepare→start) to pre-arm the AVAudioRecorder.

## Codebase Map (Files Touched)

### Modified
- `native/MuesliNative/Package.swift` — Zero deps, MuesliNativeApp + MuesliSystemAudio targets only
- `native/MuesliNative/Sources/MuesliNativeApp/TranscriptionRuntime.swift` — TranscriptionCoordinator wraps PythonWorkerClient
- `native/MuesliNative/Sources/MuesliNativeApp/Models.swift` — BackendOption + AppConfig with robust decoder
- `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift` — Central orchestrator, uses BackendOption + PythonWorkerClient
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingSession.swift` — Uses BackendOption for transcription
- `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift` — selectedBackend (no MLXAudio)
- `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift` — Single backend picker
- `native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift` — Backend submenu
- `native/MuesliNative/Sources/MuesliNativeApp/RuntimePaths.swift` — Python paths restored
- `scripts/build_native_app.sh` — swift build, bundles worker.py, install confirmation

### Created
- `CLAUDE.md` — Project documentation
- `benchmarks/bench_mlx.py` — Python MLX benchmark
- `benchmarks/run_bench.sh` — Comparison runner
- `native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClientAsync.swift` — Async wrapper

### Read / Referenced
- `bridge/worker.py` — Python worker subprocess (JSON over stdin/stdout IPC)
- `.venv/lib/python3.13/site-packages/mlx_whisper/` — Apple's mlx-whisper source (3,339 lines total)
- `native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClient.swift` — Restored from main, subprocess management

### Deleted (this session)
- `LocalPackages/mlx-swift-audio/` and `LocalPackages/swift-tiktoken/` — Patched community packages, no longer needed
- `Sources/MLXBench/` and `Sources/WhisperKitBench/` — Benchmark executables for MLX Swift/WhisperKit
- `Tests/MuesliTests/` — Test suite that depended on MLXAudio
- `/Applications/Muesli-native.app` — MLX Swift app bundle (98MB)

## Next Steps

1. **Recreate test suite without MLXAudio dependency** — The 42 tests we wrote (ModelsTests, ConfigStoreTests, DictationStoreTests, TranscriptFormatterTests, TranscriptionRuntimeTests) were deleted when we removed MLXAudio. They need to be recreated at `native/MuesliNative/Tests/MuesliTests/` targeting the Python-backend version. Tests for TranscriptionCoordinator should mock PythonWorkerClient.

2. **Fix config file pollution** — Tests write to real `~/Library/Application Support/Muesli/` database and config. DictationStore and ConfigStore need injectable paths for testing (pass URL in init instead of using AppIdentity.supportDirectoryURL).

3. **Add Parakeet/Qwen model support in Python worker** — `bridge/worker.py` currently handles `whisper` and `qwen` backends. Parakeet (from Blaizzy/mlx-audio, 666k downloads) should be added as a third backend option.

4. **Meeting transcription segments** — Python worker returns text only, no timestamps. This means meeting transcript merge shows all mic text at `[00:00:00]` and all system text at `[00:00:00]`. Need to either (a) return segments from Python worker, or (b) split text into timed chunks based on audio duration.

5. **Push main to origin** — Current main has the merged coreml-swift changes but hasn't been pushed. Run `git push origin main` when ready.

6. **Delete remote coreml-swift branch** — `git push origin --delete coreml-swift` after pushing main.

7. **Future: Pure Swift MLX port** — If revisiting, the path is to port Apple's `mlx_whisper/decoding.py` (741 lines) + `transcribe.py` (543 lines) line-by-line to Swift using mlx-swift bindings. The current community port reimplemented the architecture differently — a faithful translation should match Python performance.

## Open Questions
- Should the `coreml-swift` remote branch be deleted or kept as an archive of the MLX Swift experiment?
- Should we add a `--no-confirm` flag to `build_native_app.sh` for CI/automated builds?
- The user mentioned wanting to compare Muesli vs Muesli-native side-by-side — now that native is deleted, do we need to preserve the MLX Swift benchmark data anywhere?
