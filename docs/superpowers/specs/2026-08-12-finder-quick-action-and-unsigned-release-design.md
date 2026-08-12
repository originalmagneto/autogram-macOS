# Finder Quick Action and Unsigned Release Design

## Contract

Autogram macOS must install a Finder Quick Action that appears for selected PDF files without requiring Automator. Settings must show installation progress and a clear success or failure result. GitHub must publish an unsigned preview DMG with a checksum, release notes, and an explicit Gatekeeper warning.

## Finder Quick Action

The managed workflow remains in `~/Library/Services/Sign PDFs Autogram.workflow`. Its Automator metadata identifies it as a Finder services-menu workflow accepting PDF filesystem objects. Installation atomically replaces the workflow, refreshes the macOS Services database, and verifies that the installed metadata still identifies Finder and PDF input.

Settings performs installation asynchronously. While it runs, controls are disabled and an indeterminate progress indicator is visible. Success displays `Finder Quick Action ready`. Failure displays a specific message. A reveal button opens the installed workflow in Finder. The legacy user-created action remains untouched.

## Unsigned GitHub Release

The preview workflow builds on Apple silicon with JDK 25 and Xcode 27. It must not depend on `rg` being preinstalled. A `native-v*` tag publishes the unsigned DMG and SHA-256 checksum to a GitHub Release. Release notes are generated from GitHub history and begin with an unsigned preview warning plus installation instructions using Control-click and Open.

The release artifact is named as Autogram macOS rather than a generic native preview. No Developer ID or notarization is claimed.

## Proof

- Focused installer tests pass.
- The installed workflow contains Finder services-menu and PDF input metadata.
- The macOS Services database lists `Sign PDFs Autogram` for `com.adobe.pdf`.
- Settings exposes progress, success, failure, and reveal states.
- The GitHub workflow completes and the release contains the DMG, checksum, changelog, and unsigned warning.

