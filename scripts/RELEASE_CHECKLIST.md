# Useful Keyboard Release Checklist

Run `./scripts/release.sh [version]` — it automates steps 1-9 and is the only official release path.

Source of truth:
- GitHub Releases hosts the official DMG binaries
- GitHub Pages hosts the Sparkle appcast consumed by the app
- `gokulb20/homebrew-useful-keyboard` mirrors the verified GitHub Release DMG via the personal tap cask
- Marketing surfaces may link to those assets, but they are not release authorities

This checklist is for **verification** after the script runs, and for manual recovery if any step fails.

## Pre-release

- [ ] All changes merged to `main`
- [ ] `swift test --package-path native/UsefulKeyboard` — all tests pass
- [ ] Version bumped in `scripts/build_native_app.sh` (CFBundleVersion + CFBundleShortVersionString)
- [ ] No uncommitted changes (`git status` clean)

## Build & Sign

- [ ] `scripts/build_native_app.sh` completes without error
- [ ] App installed to `/Applications/Useful Keyboard.app`
- [ ] Verify signature: `codesign -dvvv /Applications/Useful Keyboard.app 2>&1 | grep "Authority"`
  - Must show `Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)`

## Notarize & Staple (CRITICAL ORDER)

**The app bundle must be stapled BEFORE the DMG is created. Failure to do this causes "damaged app" errors.**

- [ ] **Step 1: Notarize the app bundle**
  ```bash
  ditto -c -k --keepParent /Applications/Useful Keyboard.app Useful-Keyboard-app.zip
  xcrun notarytool submit Useful-Keyboard-app.zip --keychain-profile UsefulKeyboardNotary --wait
  ```
  - Must show `status: Accepted`

- [ ] **Step 2: Staple the app bundle**
  ```bash
  xcrun stapler staple /Applications/Useful Keyboard.app
  ```
  - Must show `The staple and validate action worked!`

- [ ] **Step 3: Create DMG from the STAPLED app**
  ```bash
  ./scripts/create_dmg.sh /Applications/Useful Keyboard.app dist-release
  ```

- [ ] **Step 4: Notarize the DMG**
  ```bash
  xcrun notarytool submit dist-release/Useful-Keyboard-X.Y.Z.dmg --keychain-profile UsefulKeyboardNotary --wait
  ```
  - Must show `status: Accepted`

- [ ] **Step 5: Staple the DMG**
  ```bash
  xcrun stapler staple dist-release/Useful-Keyboard-X.Y.Z.dmg
  ```

## Verify (DO NOT SKIP)

- [ ] **Mount the DMG and test the app inside it:**
  ```bash
  hdiutil attach dist-release/Useful-Keyboard-X.Y.Z.dmg
  spctl -a -vv "/Volumes/Useful Keyboard/Useful Keyboard.app"
  ```
  - Must show `accepted` and `source=Notarized Developer ID`
  - If it shows `rejected` — the app wasn't stapled before DMG creation. Go back to step 2.

- [ ] **Verify DMG has hardened runtime:**
  ```bash
  codesign -dvvv dist-release/Useful-Keyboard-X.Y.Z.dmg 2>&1 | grep "flags"
  ```
  - Must show `flags=0x10000(runtime)` — if missing, `create_dmg.sh` is broken

- [ ] **Install and launch:**
  ```bash
  cp -R "/Volumes/Useful Keyboard/Useful Keyboard.app" /Applications/Useful Keyboard.app
  open /Applications/Useful Keyboard.app
  ```
  - No Gatekeeper warnings
  - App launches normally
  - Existing data (dictations, meetings) is intact

- [ ] **Verify version:**
  ```bash
  defaults read /Applications/Useful Keyboard.app/Contents/Info.plist CFBundleShortVersionString
  ```

## Release Staging

- [ ] **Create a draft GitHub Release and upload the DMG**
- [ ] **Re-download the hosted draft DMG and verify it matches the local artifact**
  ```bash
  gh release download vX.Y.Z -p "Useful-Keyboard-X.Y.Z.dmg" -D /tmp/uk-release-verify --clobber
  shasum -a 256 dist-release/Useful-Keyboard-X.Y.Z.dmg /tmp/uk-release-verify/Useful-Keyboard-X.Y.Z.dmg
  spctl -a -vv -t open --context context:primary-signature /tmp/uk-release-verify/Useful-Keyboard-X.Y.Z.dmg
  xcrun stapler validate /tmp/uk-release-verify/Useful-Keyboard-X.Y.Z.dmg
  ```
  - The local and hosted SHA256 hashes must match exactly
  - Must show `accepted` and `The validate action worked!`

- [ ] **Publish the verified draft release**

## Appcast & Docs

- [ ] **Generate appcast on the single Sparkle host:**
  ```bash
  native/UsefulKeyboard/.build/artifacts/sparkle/Sparkle/bin/generate_appcast dist-release/ -o docs/appcast.xml
  ```

- [ ] **Fix appcast enclosure URLs to GitHub Releases** — `generate_appcast` writes GitHub Pages URLs. Replace with GitHub Releases URLs:
  ```
  https://gokulb20.github.io/useful-keyboard/Useful-Keyboard-X.Y.Z.dmg
  →
  https://github.com/gokulb20/useful-keyboard/releases/download/vX.Y.Z/Useful-Keyboard-X.Y.Z.dmg
  ```

- [ ] **Remove delta entries** from appcast (deltas aren't hosted)

- [ ] **Update download link** in `docs/index.html` (both the `<a>` href and JSON-LD `downloadUrl`)

- [ ] **Push appcast + download link:**
  ```bash
  git add docs/appcast.xml docs/index.html
  git commit -m "Update appcast for vX.Y.Z"
  git push
  ```

## Personal Tap

- [ ] **Update the personal Homebrew tap cask** in `gokulb20/homebrew-useful-keyboard`
  - `Casks/u/useful-keyboard.rb` must point at the new version and the hosted GitHub Release SHA256
  - Commit message should be `useful-keyboard X.Y.Z`
  - The canonical release flow now automates this inside `scripts/release.sh`

- [ ] **Verify the tap install path if the cask changed shape**
  ```bash
  brew tap gokulb20/useful-keyboard
  brew install --cask gokulb20/useful-keyboard/useful-keyboard
  ```

## Post-release

- [ ] Verify GitHub Pages serves appcast: `curl -s https://gokulb20.github.io/useful-keyboard/appcast.xml | head -5`
- [ ] Verify the GitHub Release page exposes the DMG you just uploaded
- [ ] Verify `docs/index.html` and `docs/llms.txt` point to the newly published GitHub Release DMG
- [ ] Optional: install previous version and confirm Sparkle shows update prompt
