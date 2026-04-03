#!/usr/bin/env bash
set -euo pipefail

if command -v useful-keyboard-cli >/dev/null 2>&1; then
  command -v useful-keyboard-cli
  exit 0
fi

if [[ -x "/Applications/Useful Keyboard.app/Contents/MacOS/useful-keyboard-cli" ]]; then
  echo "/Applications/Useful Keyboard.app/Contents/MacOS/useful-keyboard-cli"
  exit 0
fi

if [[ -x "native/Useful KeyboardNative/.build/debug/useful-keyboard-cli" ]]; then
  echo "$(pwd)/native/Useful KeyboardNative/.build/debug/useful-keyboard-cli"
  exit 0
fi

if [[ -x "native/Useful KeyboardNative/.build/release/useful-keyboard-cli" ]]; then
  echo "$(pwd)/native/Useful KeyboardNative/.build/release/useful-keyboard-cli"
  exit 0
fi

exit 1
