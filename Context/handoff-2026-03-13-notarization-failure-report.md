# Context Handover — Native notarization flow is wired, but the current build fails Apple notarization

**Session Date:** 2026-03-13 09:49
**Repository:** muesli
**Branch:** coreml-swift

---

## Session Objective

Record the exact notarization failure state for the current native Muesli app so it can be revisited later, likely after the CoreML/Swift backend port is more complete and the app is more self-contained.

## What Got Done
- [scripts/store_notary_profile.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/store_notary_profile.sh) — added a helper to store Apple notary credentials in Keychain via `xcrun notarytool store-credentials`.
- [scripts/notarize_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh) — added a notarization script that zips `/Applications/Muesli.app`, submits it with `notarytool`, waits, staples, validates, and runs `spctl`.
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — updated to sign `/Applications/Muesli.app` with the real Developer ID identity by default:
  - `Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)`
- Verified the installed app is now Developer ID signed:
  - `Authority=Developer ID Application: Pranav Hari Guruvayurappan (58W55QJ567)`
  - `TeamIdentifier=58W55QJ567`

## What Didn't Work
- **Notarization submission**: ran [notarize_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh) against `/Applications/Muesli.app` → Apple accepted upload but returned `Invalid` → stapling failed because no notarization ticket was issued.

## Key Decisions
- **Decision**: do not keep grinding on notarization until the native/CoreML/Swift port is further along.
  - **Context**: the current native app still depends on mixed packaging/signing assumptions and nested binaries that are not yet cleanly release-shaped.
  - **Rationale**: the failure reasons are now known precisely; fixing them later in a cleaner native release pipeline is lower risk than patching the current transitional build aggressively.
  - **Alternatives rejected**: continuing to iterate blindly on notarization without preserving the exact Apple rejection output.

## Lessons Learned
- Getting a Developer ID signature in place was necessary but not sufficient; notarization has stricter requirements than ordinary signing.
- Nested executables inside the app bundle must be signed correctly too, not just the top-level app binary.
- Hardened runtime is mandatory for notarization.

## Nuances & Edge Cases
- Notary profile is already stored in Keychain under:
  - `MuesliNotary`
- The app path used for submission was:
  - `/Applications/Muesli.app`
- The notarization archive created by the script was:
  - `dist-notary/Muesli-notarize.zip`
- Submission ID:
  - `cbeb314f-fe96-4ca5-91cc-9c238a8170f1`

### Apple Notary Result
- `status`: `Invalid`
- `statusSummary`: `Archive contains critical validation errors`
- `statusCode`: `4000`

### Exact Apple-reported issues
1. `Muesli-notarize.zip/Muesli.app/Contents/MacOS/Muesli`
   - `The executable does not have the hardened runtime enabled.`
2. `Muesli-notarize.zip/Muesli.app/Contents/Resources/MuesliSystemAudio`
   - `The binary is not signed with a valid Developer ID certificate.`
3. `Muesli-notarize.zip/Muesli.app/Contents/Resources/MuesliSystemAudio`
   - `The signature does not include a secure timestamp.`
4. `Muesli-notarize.zip/Muesli.app/Contents/Resources/MuesliSystemAudio`
   - `The executable does not have the hardened runtime enabled.`
5. `Muesli-notarize.zip/Muesli.app/Contents/Resources/MuesliSystemAudio`
   - `The executable requests the com.apple.security.get-task-allow entitlement.`

## Codebase Map (Files Touched)

### Modified
- [scripts/build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) — now signs with the real Developer ID certificate by default.

### Added
- [scripts/store_notary_profile.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/store_notary_profile.sh) — stores `notarytool` credentials in Keychain.
- [scripts/notarize_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh) — submit/staple/validate workflow for notarization.

### Read / Referenced
- Apple notary log for submission `cbeb314f-fe96-4ca5-91cc-9c238a8170f1` — source of the exact rejection reasons above.

## Next Steps
1. **Harden release signing** — update [build_native_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/build_native_app.sh) so the top-level app and nested binaries are signed with `--options runtime` and secure timestamps.
2. **Fix nested binary signing** — explicitly sign `Contents/Resources/MuesliSystemAudio` with the same Developer ID identity before signing the app bundle.
3. **Remove `get-task-allow` from release binaries** — especially for `MuesliSystemAudio`; this likely comes from the debug build profile and needs a proper release-style build configuration.
4. **Retry notarization after the native/CoreML port is more complete** — once the app is more self-contained and the release packaging path is stabilized.
5. **After success, staple and verify** — rerun [scripts/notarize_app.sh](/Users/pranavhari/Desktop/hacks/muesli/scripts/notarize_app.sh) and confirm:
   - `xcrun stapler validate /Applications/Muesli.app`
   - `spctl -a -vv /Applications/Muesli.app`

## Open Questions
- Does `MuesliSystemAudio` inherit `get-task-allow` from the current Swift build configuration, or is it being signed incorrectly after build?
- Should release notarization wait until Python worker dependencies are reduced further, so the entire app bundle is closer to the intended final native architecture?
