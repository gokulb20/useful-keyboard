---
name: useful-keyboard-agent
description: Use when working with local Useful Keyboard meetings, notes, dictations, or raw transcripts through the bundled `useful-keyboard-cli` CLI. Prefer this skill when a coding agent needs to inspect transcripts, summarize meetings with its own model, or write notes back into Useful Keyboard without requiring the user's API keys.
---

# Useful Keyboard Agent

Use the local `useful-keyboard-cli` CLI as the source of truth for meeting and dictation data.

## CLI discovery

Resolve the binary in this order:
1. `command -v useful-keyboard-cli`
2. `/Applications/Useful Keyboard.app/Contents/MacOS/useful-keyboard-cli`
3. A local SwiftPM build path inside this repo

If discovery is uncertain, run `useful-keyboard-cli info` first.

## Core workflow

1. Inspect capabilities with `useful-keyboard-cli spec` if you do not know the exact subcommand shape.
2. List candidate meetings with `useful-keyboard-cli meetings list --limit 10`.
3. Fetch a full record with `useful-keyboard-cli meetings get <id>`.
4. Use the coding agent's own model to analyze `rawTranscript` and `formattedNotes`.
5. If you want to persist improved notes, write markdown back with:
   - `cat notes.md | useful-keyboard-cli meetings update-notes <id> --stdin`
   - or `useful-keyboard-cli meetings update-notes <id> --file notes.md`

## Rules

- Treat CLI stdout as the machine-readable API. It is JSON by default.
- Treat stderr as informational only.
- Do not mutate `rawTranscript`; only update `formattedNotes`.
- Prefer the meeting transcript when `notesState` is `missing` or `raw_transcript_fallback`.
- Use `--db-path` or `--support-dir` only when the default Useful Keyboard data location is wrong.

## When to read references

Read `references/cli-contract.md` if you need the exact command tree, field definitions, or failure behavior.
