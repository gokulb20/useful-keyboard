#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${1:-${UK_NOTARY_PROFILE:-UsefulKeyboardNotary}}"
APPLE_ID="${APPLE_ID:-${UK_APPLE_ID:-}}"
TEAM_ID="${APPLE_TEAM_ID:-${UK_TEAM_ID:-58W55QJ567}}"
APP_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-${UK_APP_SPECIFIC_PASSWORD:-}}"

if [[ -z "$APPLE_ID" ]]; then
  echo "Set APPLE_ID or UK_APPLE_ID before storing a notary profile." >&2
  exit 1
fi

ARGS=(
  store-credentials
  "$PROFILE_NAME"
  --apple-id "$APPLE_ID"
  --team-id "$TEAM_ID"
)

if [[ -n "$APP_PASSWORD" ]]; then
  ARGS+=(--password "$APP_PASSWORD")
else
  echo "No app-specific password provided; notarytool will prompt securely." >&2
fi

echo "Storing notarytool keychain profile: $PROFILE_NAME"
xcrun notarytool "${ARGS[@]}"

