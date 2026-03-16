<p align="center">
  <img src="assets/muesli_app_icon.png" alt="Muesli" width="128" height="128" />
</p>

<h1 align="center">Muesli</h1>

<p align="center">
  <strong>Local-first dictation & meeting transcription for macOS</strong><br>
  100% on-device speech-to-text · Zero cloud costs · Privacy by default
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <a href="https://buymeacoffee.com/phequals7"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buymeacoffee&logoColor=white" alt="Buy Me A Coffee" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014.2%2B-lightgrey?logo=apple" alt="macOS 14.2+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-optimized-green" alt="Apple Silicon" />
</p>

---

## What is Muesli?

Muesli is a **32MB native macOS app** that combines **WisprFlow-style dictation** and **Granola-style meeting transcription** in one lightweight tool. All transcription runs locally on Apple Silicon — your audio never leaves your device.

### Dictation
Hold your hotkey (or double-tap for hands-free mode) → speak → release → transcribed text is pasted at your cursor. **~0.13 second latency** via Parakeet TDT on the Apple Neural Engine.

### Meeting Transcription
Start a meeting recording → Muesli captures your mic (You) and system audio (Others) simultaneously → chunked transcription happens during the meeting → when you stop, the transcript is ready in seconds, not minutes. Optionally generate structured meeting notes via OpenAI or free OpenRouter models.

---

## Features

- **Native Swift, zero Python** — Pure Swift app with CoreML and Metal backends. No bundled runtimes, no subprocess IPC. 32MB total.
- **Multiple ASR models** — Choose from Parakeet TDT (Neural Engine), Whisper Small/Medium/Large Turbo (Metal via whisper.cpp), with more coming soon.
- **Hold-to-talk & hands-free** — Hold hotkey for quick dictation, or double-tap for sustained recording.
- **Meeting recording** — Captures mic + system audio (including Bluetooth/AirPods) via ScreenCaptureKit.
- **Chunked meeting transcription** — Mic audio transcribed in 30-second chunks during the meeting. Only system audio needs processing at the end.
- **Silero VAD** — Neural voice activity detection skips silent chunks, preventing hallucinations.
- **Filler word removal** — Automatically strips "uh", "um", "er", "hmm" and verbal disfluencies.
- **AI meeting notes** — BYOK (Bring Your Own Key) with OpenAI or OpenRouter. Auto-generated meeting titles. Re-summarize any meeting.
- **Personal dictionary** — Add custom words and replacement pairs. Jaro-Winkler fuzzy matching auto-corrects transcription output.
- **Model management** — Download, delete, and switch between models from the Models tab. Background downloads that don't block the app.
- **Meeting auto-detection** — Detects when Zoom, Chrome, Teams, FaceTime, or Slack activates the mic. Shows a notification to start recording.
- **Configurable hotkeys** — Choose any modifier key (Cmd, Option, Ctrl, Fn, Shift) for dictation.
- **Onboarding** — First-launch wizard with model selection, permissions setup, hotkey configuration, and optional API key entry.
- **Dark & light mode** — Adaptive theme with toggle in Settings.
- **SwiftUI dashboard** — Dictation history, meeting notes (Notes-style split view), dictionary, models, shortcuts, settings, about page.
- **Floating indicator** — Draggable pill showing recording state, waveform animation, click-to-stop for meetings.

---

## Install

### Download (recommended)

Download the latest `.dmg` from [Releases](https://github.com/pHequals7/muesli/releases), open it, and drag Muesli to your Applications folder.

### Build from source

**Requirements:** macOS 14.2+, Xcode 16+

```bash
# Clone
git clone https://github.com/pHequals7/muesli.git
cd muesli

# Build and install to /Applications
./scripts/build_native_app.sh
```

The transcription model (~250MB for Parakeet v3) downloads automatically on first use.

---

## Models

| Model | Backend | Runtime | Size | Languages |
|-------|---------|---------|------|-----------|
| **Parakeet v3** (recommended) | FluidAudio | CoreML / Neural Engine | ~250 MB | 25 languages |
| Parakeet v2 | FluidAudio | CoreML / Neural Engine | ~250 MB | English only |
| Whisper Small | whisper.cpp | Metal / CPU | ~190 MB | English only |
| Whisper Medium | whisper.cpp | Metal / CPU | ~1.5 GB | English only |
| Whisper Large Turbo | whisper.cpp | Metal / CPU | ~600 MB | Multilingual |

Models download on demand from HuggingFace. Manage them from the **Models** tab in the dashboard.

---

## Permissions

Muesli needs these macOS permissions (guided during onboarding):

| Permission | Why |
|---|---|
| **Microphone** | Record audio for dictation and meetings |
| **System Audio Recording** | Capture call audio from Zoom/Meet/Teams |
| **Accessibility** | Simulate Cmd+V to paste transcribed text |
| **Input Monitoring** | Detect hotkey presses globally |
| **Calendar** *(optional)* | Auto-detect upcoming meetings |

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Native Swift / SwiftUI App (32MB)               │
│  ├── FluidAudio (Parakeet TDT on Neural Engine)  │
│  ├── SwiftWhisper (whisper.cpp on Metal/CPU)      │
│  ├── Silero VAD (voice activity detection)        │
│  ├── FillerWordFilter (uh/um removal)             │
│  ├── CustomWordMatcher (Jaro-Winkler fuzzy)       │
│  ├── HotkeyMonitor (configurable modifier keys)   │
│  ├── MicrophoneRecorder (AVAudioRecorder)         │
│  ├── SystemAudioRecorder (ScreenCaptureKit)       │
│  ├── MeetingSession (chunked transcription)       │
│  ├── MeetingSummaryClient (OpenAI / OpenRouter)   │
│  ├── FloatingIndicatorController (UI pill)        │
│  └── SwiftUI Dashboard (dictations, meetings,     │
│       dictionary, models, shortcuts, settings)    │
└──────────────────────────────────────────────────┘
```

Everything runs in-process. No subprocesses, no IPC, no Python runtime.

---

## Tech Stack

| Component | Technology |
|---|---|
| App | Swift, AppKit, SwiftUI |
| Primary ASR | [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT on CoreML/ANE) |
| Whisper ASR | [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) (whisper.cpp on Metal) |
| Voice activity | Silero VAD via FluidAudio |
| System audio | ScreenCaptureKit (`SCStream`) |
| Meeting notes | OpenAI / OpenRouter (BYOK) |
| Word correction | Jaro-Winkler similarity (native Swift) |
| Storage | SQLite (WAL mode) |
| Signing | Developer ID + hardened runtime (notarization ready) |

---

## Contributing

Contributions welcome! To get started:

```bash
git clone https://github.com/pHequals7/muesli.git
cd muesli
swift build --package-path native/MuesliNative -c release
swift test --package-path native/MuesliNative
```

86 tests covering model configuration, custom word matching, filler removal, transcription routing, and data persistence.

Please open an issue before submitting large PRs.

---

## Support

If Muesli saves you time, consider supporting development:

<a href="https://buymeacoffee.com/phequals7"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=for-the-badge&logo=buymeacoffee&logoColor=white" alt="Buy Me A Coffee" /></a>

---

## Acknowledgements

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — CoreML speech models for Apple devices (Parakeet TDT, Silero VAD)
- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) — Swift wrapper for whisper.cpp
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — C/C++ Whisper inference
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) by Apple — system audio capture
- [NVIDIA Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — FastConformer TDT speech recognition model

---

## License

[MIT](LICENSE) — free and open source.
