# Building Useful Keyboard

## Prerequisites

- [Rust](https://rustup.rs/) (latest stable)
- [Bun](https://bun.sh/)
- Xcode Command Line Tools (macOS) / Visual Studio Build Tools (Windows)

## Run Locally

```bash
bun install
CMAKE_POLICY_VERSION_MINIMUM=3.5 bun run tauri dev
```

## Build Locally

```bash
bun install
bun run tauri build
```

Artifacts land in `src-tauri/target/release/bundle/`:

| Platform | Path |
|----------|------|
| macOS DMG | `bundle/dmg/*.dmg` |
| macOS App | `bundle/macos/*.app` |
| Windows MSI | `bundle/msi/*.msi` |
| Windows NSIS | `bundle/nsis/*.exe` |

For a cross-compile on macOS ARM64:

```bash
bun run tauri build --target aarch64-apple-darwin
# Artifacts in src-tauri/target/aarch64-apple-darwin/release/bundle/
```

## Release

Tag and push to trigger the unsigned release workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

This runs `.github/workflows/release-unsigned.yml`, which builds for
macOS (ARM64) and Windows (x64), then creates a GitHub Release with
the artifacts attached.

v0.1 ships unsigned. On macOS: right-click > Open on first launch.
On Windows: dismiss the SmartScreen warning.

See `BUILD_NOTES.md` for code signing and model CDN migration TODOs.
