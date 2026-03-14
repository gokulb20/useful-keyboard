# Context Handover — Voice Animation Research + Aawaaz Comparison + VAD Runtime Analysis

**Session Date:** 2026-03-14 20:42
**Repository:** muesli
**Branch:** `coreml-swift` (work done here; currently on `main` after checkout)

---

## Session Objective
Three research tasks (no code written this session):
1. Merge `ui-frontend` branch into `coreml-swift` and push to remote
2. Research how WisprFlow and Handy implement voice-reactive listening animations, determine best native approach for Muesli's floating indicator
3. Deep comparison of Aawaaz (github.com/shantanugoel/aawaaz) vs Muesli — architecture, features, what to learn
4. Evaluate whisper.cpp vs WhisperKit vs mlx-whisper performance, and whether streaming VAD adds meaningful overhead
5. Find native Swift Silero VAD implementations that avoid ONNX Runtime

## What Got Done
- **Merged `ui-frontend` → `coreml-swift`** — fast-forward merge of commit `81924b9`, pushed to `origin/coreml-swift`
- **Reverse-engineered WisprFlow's waveform animation** from `/Applications/Wispr Flow.app/Contents/Resources/app.asar`:
  - Two-layer system: base CSS `scaleY(0.3→1)` loop (always running) + real-time audio amplitude scaling
  - Audio pipeline: `RecorderProcessor` AudioWorklet (640-sample chunks) → `He()` RMS→dB function (`20 * log10(rms + 1e-10)`) → IPC with `{volume: dB}` → renderer exponential smoothing (`displayed * 0.7 + incoming * 0.3`) → 7 bars, bar[i] active if `smoothedLevel > i/7`
  - Key files in asar: `recorderWorklet.js`, `He()` in main process bundle, `DT` component in hub renderer
- **Analyzed Handy app** (`/Applications/Handy.app`) — Tauri/Rust, `visualizer.rs` calculates RMS, sends `mic-level` via IPC, JS animates dots. Simpler: no idle animation, purely amplitude-driven.
- **Determined ideal Muesli implementation**: `AVAudioRecorder.averagePower(forChannel:)` + CALayer bar sublayers + two-layer animation. ~60-80 lines across 3 files. See detailed plan in `Context/handoff-summary-2026-03-14-201441.md`.
- **Comprehensive Aawaaz comparison** — full codebase analysis of 30+ Swift files. Key findings documented below.
- **Whisper engine benchmarks collected** — M4 Pro large-v3-turbo: mlx-whisper 1.02s, whisper.cpp 1.23s, WhisperKit 2.22s
- **Found native Swift Silero VAD** — no ONNX Runtime needed:
  - **FluidAudio** (CoreML, 0.7MB model, Neural Engine, `~40μs/chunk`)
  - **speech-swift** (MLX, 1.2MB model, GPU via Metal, `~40μs/chunk`)

## Key Decisions

- **Decision**: Use `AVAudioRecorder.averagePower` for voice animation (not AVAudioEngine)
  - **Context**: Need mic audio levels to drive waveform bars in floating indicator
  - **Rationale**: Already recording with AVAudioRecorder. Metering is one flag flip (`isMeteringEnabled = true`). Apple computes RMS+dB internally.
  - **Alternatives rejected**: AVAudioEngine (separate audio pipeline, overkill for amplitude), Core Audio C API (massive complexity)

- **Decision**: CALayer sublayers for bar rendering (not SwiftUI)
  - **Context**: FloatingIndicatorController is entirely CALayer-based
  - **Rationale**: Adding CAShapeLayer bars keeps same paradigm, GPU-composited, zero SwiftUI hosting overhead
  - **Alternatives rejected**: SwiftUI NSHostingView overlay (framework crossing for 7 bars), NSView.draw() (CPU-drawn)

- **Decision**: Two-layer animation (WisprFlow pattern)
  - **Context**: User confirmed WisprFlow has gentle idle wave + voice-reactive amplitude
  - **Rationale**: `CABasicAnimation` with `autoreverses`/`repeatCount = .infinity` for base oscillation (GPU render server, zero main thread cost). `CADisplayLink` polls `averagePower` for amplitude envelope.

- **Decision**: If adding VAD, use CoreML (FluidAudio) or MLX (speech-swift) — NOT ONNX Runtime
  - **Context**: Aawaaz uses ONNX Runtime for Silero VAD, which is a heavy dependency
  - **Rationale**: Both FluidAudio and speech-swift provide Silero VAD v5 as native Swift packages. FluidAudio on CoreML matches WhisperKit's hardware path (Neural Engine). speech-swift on MLX is viable if moving transcription to MLX too.
  - **Alternatives rejected**: ONNX Runtime (30-50MB dependency bloat for a 2.3MB model)

## Lessons Learned

- **WisprFlow's waveform is NOT just a CSS loop** — user corrected initial analysis. It has real audio reactivity via AudioWorklet → RMS → IPC → smoothing → bar activation. The CSS loop is just the idle baseline.
- **Exponential smoothing 0.7/0.3** is the proven constant for voice animation responsiveness (WisprFlow uses this exact ratio).
- **WhisperKit is slower than whisper.cpp and mlx-whisper on short clips** (2.22s vs 1.23s vs 1.02s on M4 Pro). CoreML dispatch latency hurts for short dictation audio. WhisperKit wins on sustained longer recordings.
- **Silero VAD overhead is negligible**: ~0.4% of one CPU core for real-time processing. The cost of VAD is architectural complexity (streaming pipeline), not compute.
- **Pragmatic VAD middle ground**: Run VAD post-recording on complete WAV to strip silence before Whisper. Gets ~30-40% of the speed benefit with ~5% of streaming VAD's complexity.
- **Aawaaz's clipboard save/restore** is a trivial win (~20 lines) that Muesli should adopt — deep-copy all pasteboard items before Cmd+V, restore after 100ms.

## Nuances & Edge Cases

- `AVAudioRecorder.updateMeters()` MUST be called before each `averagePower` read — it doesn't auto-update
- `averagePower` returns `-160` when not recording — safe default, no crash risk
- Staggered `beginTime` for base oscillation: use `CACurrentMediaTime() + offset` per bar, not absolute times
- CABasicAnimation on NSPanel layers: test with `collectionBehavior: [.canJoinAllSpaces]` to ensure animations don't pause on macOS space switch
- Two app bundles exist: `Muesli.app` (bundle ID `com.muesli.app`) and `muesli-native.app` (bundle ID `com.muesli.app.native`). Native app build: `MUESLI_APP_NAME="muesli-native" MUESLI_DISPLAY_NAME="muesli-native" MUESLI_APP_BUNDLE_NAME="muesli-native.app" MUESLI_EXECUTABLE_NAME="MuesliNative" MUESLI_BUNDLE_ID="com.muesli.app.native" ./scripts/build_native_app.sh release`

## Aawaaz vs Muesli — Key Takeaways

### Aawaaz advantages over Muesli:
| Feature | Aawaaz | Muesli |
|---|---|---|
| Audio capture | AVAudioEngine (streaming) | AVAudioRecorder (file-based WAV) |
| VAD | Silero VAD v5 (real-time, during recording) | None |
| Text insertion | 3-strategy cascade (AX API → Cmd+V → clipboard) + clipboard save/restore | Clipboard + Cmd+V only |
| Post-processing | On-device Qwen 3 LLM (filler removal, grammar, context-aware formatting) | None for dictation |
| Hotkey | CGEvent tap (suppresses key) + configurable via UI | NSEvent monitors (observe-only) + hardcoded Left Cmd |
| Session isolation | UUID per session, all async callbacks check ID | None |

### Muesli advantages over Aawaaz:
- Meeting transcription (mic + system audio + merge + LLM summary) — Aawaaz has nothing
- System audio capture via AudioHardwareCreateProcessTap
- Persistent history + stats (SQLite)
- Dashboard UI with timeline-grouped dictations + meeting notes viewer
- Multiple transcription backends (WhisperKit, mlx-whisper, Qwen ASR)
- Calendar integration (auto-record meetings)

### Low-hanging fruit to adopt from Aawaaz (ordered by effort):
1. **Session UUID isolation** (~10 lines) — prevent stale async callbacks
2. **Clipboard save/restore** (~20 lines in PasteController.swift) — stop destroying user clipboard
3. **Filler word removal** (~30 lines, regex) — "um", "uh", "you know", "basically"
4. **Self-correction detection** (~50 lines) — "scratch that", "actually no", "I mean"
5. **Configurable hotkey** (medium) — replace hardcoded Left Cmd
6. **Accessibility API text insertion** (medium) — try AX API before Cmd+V fallback
7. **Onboarding wizard** (medium) — step through permissions + model download

## Codebase Map (Files Touched)

### Modified
- `coreml-swift` branch — merged `ui-frontend` commit `81924b9` (SwiftUI dashboard rebuild, 12 new files + 4 modified)

### Read / Referenced
- `native/MuesliNative/Sources/MuesliNativeApp/FloatingIndicatorController.swift` — Where voice animation bars will be added. All CALayer-based. Key: lines 88-91 (layer styling), 180-206 (frame for recording state = 164x46), 229-240 (recording style: red bg, "Listening" text)
- `native/MuesliNative/Sources/MuesliNativeApp/MicrophoneRecorder.swift` — AVAudioRecorder wrapper. Line 22: `isMeteringEnabled = false` → flip to `true`. Add `currentPower() -> Float`.
- `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift` — Orchestrator. Lines 382-395 (`handleStart`): where recording begins. Pass recorder/power to indicator.
- `native/MuesliNative/Sources/MuesliNativeApp/StatusBarController.swift` — Read for context
- `native/MuesliNative/Sources/MuesliNativeApp/PreferencesWindowController.swift` — Read for context
- `scripts/build_native_app.sh` — Build script with env var overrides

### External Repos Analyzed
- `/Applications/Wispr Flow.app` — Electron/React, decompiled app.asar for animation code
- `/Applications/Handy.app` — Tauri/Rust, analyzed binary for visualizer.rs patterns
- `github.com/shantanugoel/aawaaz` — Full Swift codebase analysis (30+ files), Xcode project, whisper.cpp + Silero VAD + Qwen 3 LLM
- `github.com/FluidInference/FluidAudio` — CoreML Silero VAD Swift package
- `github.com/soniqo/speech-swift` — MLX Silero VAD + Qwen3-ASR Swift package

## Next Steps

1. **Implement voice animation in floating indicator** — Follow detailed plan in `Context/handoff-summary-2026-03-14-201441.md`. Three files: `MicrophoneRecorder.swift` (enable metering + `currentPower()`), `FloatingIndicatorController.swift` (7 CALayer bars + base oscillation + CADisplayLink amplitude), `MuesliController.swift` (wire recorder to indicator).

2. **Add clipboard save/restore to PasteController.swift** — Before `setString`, deep-copy all `NSPasteboard.general.pasteboardItems` by reading each item's data for all types. After 100ms post-paste, restore. ~20 lines. See Aawaaz's `KeystrokeSimulator.swift` for reference pattern.

3. **Add session UUID isolation** — Add `private var sessionID = UUID()` to `MuesliController`. Set new UUID in `handleStart()`. Check `guard sessionID == capturedID` in all async callbacks in `handleStop()` (lines 428-468). ~10 lines.

4. **Evaluate VAD integration** — Start with post-recording silence trimming (run Silero VAD on complete WAV after recording stops, trim silence, send shorter audio to Whisper). Use FluidAudio (`SpeechVAD` module) for CoreML path. Graduate to streaming VAD later.

5. **Add filler word removal** — Simple regex pass on transcription output before paste: `\b(um|uh|erm|hmm|you know|basically|literally)\b` with word boundary matching. ~30 lines as a new `TextProcessor` utility.

## Open Questions
- Should waveform bars replace the "Listening" text label, sit alongside it, or replace the mic emoji? User hasn't specified layout.
- Bar count: WisprFlow uses 7, Aawaaz overlay uses 5. What fits best in Muesli's 164x46 pill?
- Should base oscillation run during `.preparing` state too, or only `.recording`?
- For VAD: FluidAudio (CoreML, matches WhisperKit hardware path) vs speech-swift (MLX, also has Qwen3-ASR)? Depends on whether transcription engine stays WhisperKit or moves to MLX.
- Should Muesli adopt whisper.cpp (like Aawaaz) for lower dispatch latency on short dictation clips? Or keep WhisperKit for Neural Engine power efficiency?
