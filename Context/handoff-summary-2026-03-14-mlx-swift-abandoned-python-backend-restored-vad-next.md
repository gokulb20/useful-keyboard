# Context Handover — MLX Swift abandoned, Python MLX restored, streaming VAD for meetings is next

**Session Date:** 2026-03-14 15:00–22:00
**Repository:** muesli
**Branch:** `main` (merged from `coreml-swift`)

---

## Session Objective
Integrate MLX Swift (mlx-swift-audio) as native transcription engine, benchmark against Python mlx-whisper, decide optimal architecture, and plan streaming VAD for meeting transcription.

## What Got Done

### MLX Swift Integration (built, benchmarked, then reverted)
- Patched `LocalPackages/mlx-swift-audio/` and `LocalPackages/swift-tiktoken/` for Swift 6.1.2 compat (tools-version 6.2→5.9, excluded TTS/FunASR/Codec, fixed `isolated deinit`)
- Rewrote `TranscriptionRuntime.swift` — `TranscriptionCoordinator` actor wrapping `WhisperEngine` from mlx-swift-audio
- Replaced `BackendOption`/`TranscriptionRuntimeOption` with `STTModelOption` enum + configurable `WhisperQuantization`
- Added quantization picker (fp16/q8/q4) to SettingsView and StatusBarController
- All files updated (MuesliController, MeetingSession, AppState, SettingsView, StatusBarController)
- Build succeeded: 168s, 91MB binary

### Benchmarking (MLX Swift vs Python mlx-whisper)
- `benchmarks/bench_mlx.py` — Python benchmark script
- `benchmarks/run_bench.sh` — Comparison runner
- `Sources/MLXBench/main.swift` — Swift benchmark executable
- Results (whisper-small.en fp16, LJ Speech 5s clip, 5 warm runs):
  - **Python mlx-whisper: 0.319s warm avg** (Apple-maintained, `mlx@group.apple.com`)
  - **MLX Swift: 1.582s warm avg** (community port, DePasqualeOrg)
  - Python 5x faster, no hallucinations vs Swift had `[BLANK_AUDIO]` and repetition artifacts
- Installed as `/Applications/Muesli-native.app` (98MB) for side-by-side testing — user confirmed it was noticeably slower

### Reverted to Python MLX backend
- `Package.swift` — Zero external dependencies
- `TranscriptionRuntime.swift` — `TranscriptionCoordinator` wraps `PythonWorkerClient` instead of `WhisperEngine`
- `PythonWorkerClient.swift` — Restored from main branch (subprocess IPC via JSON over stdin/stdout)
- `PythonWorkerClientAsync.swift` — Created async wrappers
- `Models.swift` — Reverted to `BackendOption`, added robust `init(from:)` decoder for forward-compat
- `RuntimePaths.swift` — Restored Python fields
- `build_native_app.sh` — Back to `swift build`, bundles worker.py, adds install confirmation prompt
- Build: 14.8s, binary: 1.1MB
- Cleaned up WhisperKit cache (540MB freed from `~/Library/Caches/WhisperKitBench/`)

### Branch merge and cleanup
- Merged `coreml-swift` → `main` (fast-forward, 41 files)
- Deleted `/Applications/Muesli-native.app` (98MB MLX Swift version)
- Cleared Launchpad cache
- Installed final app at `/Applications/Muesli.app` (SwiftUI frontend + Python MLX backend)

### Competitor analysis
- **Granola uses cloud STT** — Deepgram (primary, nova-2 model), Speechmatics, AssemblyAI as fallbacks. All via WebSocket streaming (`wss://api.deepgram.com/v1/listen`). NOT local.
- **Aawaaz uses local streaming VAD** — Silero VAD v5 via ONNX Runtime → whisper.cpp. 512-sample chunks (32ms windows), VADState state machine with hysteresis.
- **WisprFlow** — Electron + Swift helper app, uses cloud for transcription
- **Handy** — Native arm64, minimal entitlements (audio-input only)

### Test suite (created then removed)
- 42 tests covering Models, AppConfig, DictationStore, ConfigStore, TranscriptFormatter, TranscriptionCoordinator
- Found real bug: `AppConfig` `init(from:)` failed on missing JSON keys — fixed with custom decoder
- Tests removed when MLX dependency was dropped (they imported MLXAudio)
- **Need recreation without MLXAudio dependency**

## What Didn't Work
- **MLX Swift performance**: 5x slower than Python. Gap is in decoding loop orchestration, not GPU compute. Both use same C++ MLX engine.
- **MLX Swift accuracy**: Hallucinations on silence (`[BLANK_AUDIO]`), repetitions ("hello hello hello hello"), garbled transcriptions.
- **`swift build` + Metal**: SPM doesn't compile Metal shaders → runtime crash. Must use `xcodebuild` for MLX Swift apps.
- **Overwrote /Applications/Muesli.app**: Installed native build over user's working Python app without asking. Had to rebuild from main via `git worktree`.
- **runtime.json pointing to deleted worktree**: After `git worktree remove /tmp/muesli-main`, bundled runtime.json still referenced dead paths.
- **Config corruption from tests**: Tests wrote to real `~/Library/Application Support/Muesli/` database and config.

## Key Decisions
- **Python mlx-whisper over MLX Swift**: 5x faster, accurate, 1.1MB vs 91MB. Apple's own optimized code vs community port. Same C++ GPU engine underneath.
- **SwiftUI frontend kept**: Dark-theme dashboard (DictationsView, MeetingsView, SettingsView, sidebar navigation) merged to main. Python handles ML, Swift handles UI.
- **Streaming VAD for meetings is next priority**: Current approach records entire meeting → transcribes at end (minutes of waiting). With VAD + chunked transcription, transcript is 99% done when meeting ends.
- **Future pure Swift MLX port**: User wants a dedicated session to line-by-line port Apple's 3,339 lines of Python mlx-whisper to Swift using mlx-swift bindings. Needs a hyper-specific seed prompt.
- **Notarization deferred**: Needs hardened runtime + entitlements + Python bundling solved first. Do after feature work is complete.

## Lessons Learned
- `mlx-whisper` is Apple-maintained (`mlx@group.apple.com`, `ml-explore/mlx-examples`). The Swift port (DePasqualeOrg) is community (1 person).
- Swift HuggingFace Hub cache (`~/Library/Caches/huggingface/models/`) differs from Python (`~/.cache/huggingface/hub/`). Models can't be shared.
- A faithful line-by-line port of Apple's Python to Swift SHOULD match performance — the community port reimplemented differently rather than translating directly. Key files: `decoding.py` (741 lines), `transcribe.py` (543 lines), `timing.py` (329 lines).
- Granola's streaming transcription uses cloud APIs (Deepgram), not local models. Muesli's local approach is differentiated by privacy.
- Whisper hallucinates on silence — VAD eliminates this entire class of errors.
- NEVER install builds as `/Applications/Muesli.app` without asking. Memory saved at `memory/feedback_separate_app_bundles.md` and `memory/feedback_confirm_destructive.md`.

## Nuances & Edge Cases
- AppConfig uses custom `init(from:)` to handle missing keys gracefully — essential for config migration between versions
- Python worker's `transcribe_file` returns text only, no timestamped segments. MeetingSession creates a single segment per audio file for TranscriptFormatter.merge() compatibility.
- `build_native_app.sh` now uses `swift build` (not `xcodebuild`). Only needed xcodebuild when MLX Swift was the backend (Metal shaders).
- HotkeyMonitor has 150ms→250ms two-stage activation (prepare→start) to pre-arm AVAudioRecorder.
- Aawaaz uses ONNX Runtime for Silero VAD (~30-50MB bloat). FluidAudio (CoreML) and speech-swift (MLX) are lighter native alternatives.

## Codebase Map (Files Touched)

### Modified (final state on main)
- `native/MuesliNative/Package.swift` — Zero deps, MuesliNativeApp + MuesliSystemAudio only
- `native/MuesliNative/Sources/MuesliNativeApp/TranscriptionRuntime.swift` — TranscriptionCoordinator wraps PythonWorkerClient
- `native/MuesliNative/Sources/MuesliNativeApp/Models.swift` — BackendOption + AppConfig with robust decoder
- `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift` — Uses BackendOption + PythonWorkerClient + TranscriptionCoordinator
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingSession.swift` — Uses BackendOption, records mic+system, transcribes both, merges, summarizes
- `native/MuesliNative/Sources/MuesliNativeApp/AppState.swift` — selectedBackend (no MLXAudio)
- `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift` — Single backend picker
- `native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift` — Backend submenu
- `native/MuesliNative/Sources/MuesliNativeApp/RuntimePaths.swift` — Python paths restored
- `scripts/build_native_app.sh` — swift build, bundles worker.py, install confirmation prompt

### Created
- `CLAUDE.md` — Project documentation
- `benchmarks/bench_mlx.py` — Python MLX benchmark
- `benchmarks/run_bench.sh` — Comparison runner
- `native/MuesliNative/Sources/MuesliNativeApp/PythonWorkerClientAsync.swift` — Async wrapper

### Key files for next task (streaming VAD for meetings)
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingSession.swift` — Current batch architecture. Lines 45-51: `start()` begins mic+system recording. Lines 53-97: `stop()` transcribes both WAVs after meeting ends. This is what needs to change to streaming.
- `native/MuesliNative/Sources/MuesliNativeApp/MicrophoneRecorder.swift` — AVAudioRecorder (file-based). Needs to change to AVAudioEngine (streaming) for VAD.
- `native/MuesliNative/Sources/MuesliNativeApp/SystemAudioRecorder.swift` — Launches MuesliSystemAudio subprocess. Outputs WAV file. Needs streaming variant.
- `native/MuesliNative/Sources/MuesliNativeApp/TranscriptionRuntime.swift` — TranscriptionCoordinator currently has `transcribeMeeting(at: URL)`. Needs streaming method that accepts audio chunks.
- `native/MuesliNative/Sources/MuesliNativeApp/TranscriptFormatter.swift` — Merges mic+system segments by timestamp. Currently works with segments from batch transcription.
- `bridge/worker.py` — Python worker. Currently handles `transcribe_file`. Needs a streaming/chunked transcription method.
- `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift:310-361` — `startMeetingRecording()`/`stopMeetingRecording()` — orchestrates meeting lifecycle.

### Competitor reference
- Aawaaz VAD: `github.com/shantanugoel/aawaaz/Aawaaz/VAD/VADProcessor.swift` — Silero VAD v5 ONNX, 512-sample chunks (32ms), streams probabilities. `VADState.swift` — state machine with speech/silence thresholds, min/max duration, hysteresis.
- Aawaaz audio: `AudioCaptureManager.swift` — AVAudioEngine, 4096 buffer, converts to 16kHz mono Float32, `onSamplesReceived` callback.

## Next Steps

1. **Implement streaming VAD for meeting transcription** — The core next feature. Architecture:
   - Switch MeetingSession from AVAudioRecorder (file-based) to AVAudioEngine (streaming) for mic capture
   - Add Silero VAD (Python-side via `silero-vad` pip package, or Swift-side via FluidAudio CoreML). Python-side is simpler and consistent with "Python does ML" architecture.
   - Add `transcribe_chunk` method to `bridge/worker.py` that accepts WAV chunks and returns text
   - MeetingSession accumulates transcript segments during recording. When `stop()` is called, only the last few seconds need transcription.
   - TranscriptFormatter.merge() continues to work — segments arrive incrementally instead of at end.
   - Consider: VAD in Python (add to worker.py, receives audio stream) vs VAD in Swift (runs locally, only sends speech segments to Python). Swift-side VAD reduces IPC but adds a dependency.

2. **Recreate test suite without MLXAudio** — The 42 tests need recreation at `native/MuesliNative/Tests/MuesliTests/`. Use Swift Testing framework. Tests for TranscriptionCoordinator should mock PythonWorkerClient. Fix DictationStore/ConfigStore tests to use injectable paths (not real `~/Library/Application Support/Muesli/`).

3. **Prepare seed prompt for pure Swift MLX port** — User wants a comprehensive, hyper-specific prompt for a future Claude Code session to port Apple's `mlx_whisper/` (3,339 lines) to Swift. Key files to port: `decoding.py` (741 lines, beam search, KV cache, logit filters), `transcribe.py` (543 lines, seek-based processing), `whisper.py` (266 lines, model architecture), `timing.py` (329 lines, DTW word timestamps), `tokenizer.py` (398 lines), `audio.py` (173 lines, mel spectrogram).

4. **Notarization prep** (when ready to ship) — Add `--options runtime` to codesign, create entitlements plist (`com.apple.security.device.audio-input`, `com.apple.security.personal-information.calendars`, `com.apple.security.cs.allow-jit`, `com.apple.security.cs.allow-unsigned-executable-memory`), sign MuesliSystemAudio separately before outer app, solve Python venv bundling.

## Open Questions
- Should VAD run in Python (add to worker.py) or Swift (FluidAudio CoreML)? Python is simpler but adds IPC for audio streaming. Swift is lower latency but adds a dependency.
- For meeting streaming: should we send raw audio chunks to Python over stdin, or write temp WAV files and send paths? Raw audio is faster but requires binary protocol changes to the JSON-over-stdin IPC.
- Should the `coreml-swift` remote branch be deleted or kept as archive of the MLX Swift experiment?
- System audio (MuesliSystemAudio subprocess) currently writes to a WAV file. For streaming, it needs to pipe audio to the parent process. This may require rewriting it to use stdout instead of file output.
