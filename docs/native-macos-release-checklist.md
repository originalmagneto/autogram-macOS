# Native macOS Release Checklist

## Release identity and artifact

- [ ] Build the Apple silicon release candidate with the required native macOS toolchain.
- [ ] Sign with the approved Developer ID Application identity.
- [ ] Package the release DMG and record its SHA-256 hash.
- [ ] Submit the DMG with the approved notarytool Keychain profile.
- [ ] Confirm notarization, stapling, and Gatekeeper assessment.
- [ ] Run the native release verifier in structural, signature, and notarization modes.

## Fresh-system acceptance

- [ ] Test from a fresh macOS 27 user account.
- [ ] Install the DMG by dragging Autogram to Applications.
- [ ] Install and use the Finder Quick Action with one PDF and with multiple PDFs.
- [ ] Sign local files and cloud-synchronised files.
- [ ] Verify handling of PDFs that already contain signatures.
- [ ] Verify the user-facing outcome when the qualified timestamp authority is unavailable.

## eID and middleware acceptance

- [ ] Confirm the selected eID middleware provides an arm64 PKCS#11 library.
- [ ] Confirm I.CA SecureStore version 8.3.1 or newer when I.CA is used.
- [ ] Verify signing with the correct PIN.
- [ ] Verify rejection and recovery guidance for an incorrect PIN.
- [ ] Verify the user-facing outcome when the card is removed during the workflow.
- [ ] Verify the user-facing rejection of an x86_64-only PKCS#11 library.

## Evidence status

- [ ] Physical token testing is unverified for this release candidate.
- [ ] Live qualified timestamp authority testing is unverified for this release candidate.

Do not mark either unverified item complete until it has been exercised on the release candidate and recorded in the release notes.
