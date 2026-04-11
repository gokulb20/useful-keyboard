# Build Notes

## TODO: Model CDN Migration (before v0.2)

All model download URLs in `src-tauri/src/managers/model.rs` currently point to
`blob.handy.computer` (the upstream Handy project's CDN). This works for v0.1
because the models are identical regardless of branding, and the URLs are not
user-visible.

**Before v0.2**, set up your own blob storage (S3, R2, etc.) and update every
URL in `model.rs` from `https://blob.handy.computer/...` to your own mirror.
There are ~16 model URLs to update.

The same CDN is used for ONNX Runtime downloads in CI (see
`.github/workflows/build.yml.disabled`, lines 306 and 321). If you re-enable
signed builds, update those URLs too.

The VAD model setup command in `CLAUDE.md` also references
`https://blob.handy.computer/silero_vad_v4.onnx` -- update when hosting is ready.

## TODO: Code Signing (before v0.2)

v0.1 ships unsigned binaries. Users must right-click > Open on macOS and dismiss
SmartScreen on Windows.

**macOS**: Requires Apple Developer Program ($99/yr). Obtain a Developer ID
Application certificate. Set GitHub secrets: `APPLE_CERTIFICATE`,
`APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`.
Then restore `signingIdentity` in `tauri.conf.json` and `hardenedRuntime: true`.

**Windows**: Requires Azure Trusted Signing or an EV code signing certificate.
Restore `signCommand` in `tauri.conf.json` and configure Azure secrets in CI.

## TODO: Updater Signing Key (before v0.2)

The Tauri updater requires signed update bundles. Generate a new keypair:

```bash
bunx tauri signer generate -w ~/.tauri/useful-keyboard.key
```

Then set `pubkey` in `tauri.conf.json` under `plugins.updater` and add
`TAURI_SIGNING_PRIVATE_KEY` / `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` as GitHub
secrets. Set `createUpdaterArtifacts` back to `true`.

## Disabled Workflows

The following workflows were disabled (renamed to `.disabled`) because they
depend on code signing infrastructure from the upstream Handy project:

- `.github/workflows/release.yml.disabled` -- signed release with draft GitHub Release
- `.github/workflows/build.yml.disabled` -- reusable build with signing support

The active release workflow is `.github/workflows/release-unsigned.yml`.

Note: `main-build.yml`, `build-test.yml`, and `pr-test-build.yml` reference
the now-disabled `build.yml`. They will fail until either `build.yml` is
restored or those workflows are updated to use a new reusable build workflow.
