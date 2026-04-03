#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
INSTALL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/uk-packaging-test.XXXXXX")"
APP_BUNDLE_NAME="UsefulKeyboardPackagingTest.app"
APP_PATH="$INSTALL_ROOT/$APP_BUNDLE_NAME"
APP_BIN="$APP_PATH/Contents/MacOS/Useful Keyboard"
CLI_BIN="$APP_PATH/Contents/MacOS/useful-keyboard-cli"
SPEC_OUTPUT="$INSTALL_ROOT/useful-keyboard-cli-spec.json"

cleanup() {
  rm -rf "$INSTALL_ROOT"
}
trap cleanup EXIT

echo "Building isolated app bundle in $INSTALL_ROOT"
UK_INSTALL_DIR="$INSTALL_ROOT" \
UK_APP_BUNDLE_NAME="$APP_BUNDLE_NAME" \
UK_SKIP_SIGN=1 \
"$ROOT/scripts/build_native_app.sh" "$BUILD_CONFIG"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected packaged app at $APP_PATH" >&2
  exit 1
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing app executable at $APP_BIN" >&2
  exit 1
fi

if [[ ! -x "$CLI_BIN" ]]; then
  echo "Missing CLI executable at $CLI_BIN" >&2
  exit 1
fi

"$CLI_BIN" spec > "$SPEC_OUTPUT"

if ! grep -q '"command" : "useful-keyboard-cli spec"' "$SPEC_OUTPUT"; then
  echo "Packaged CLI did not return the expected spec payload." >&2
  cat "$SPEC_OUTPUT" >&2
  exit 1
fi

echo "Packaged CLI smoke test passed."
echo "Verified:"
echo "  - $APP_BIN"
echo "  - $CLI_BIN"
