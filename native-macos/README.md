# Autogram native macOS workspace

This directory contains the native macOS SwiftUI workspace for Autogram. It uses SwiftUI and AppKit for the application shell and PDFKit for document preview, while a bundled Java Autogram/DSS helper performs signing and validation through the machine protocol.

## Development status

The workspace is under active development. It supports PDF intake, preview, signing configuration, certificate selection, PIN entry, output handling, and the qualified timestamp signing flow. Finder Quick Action installation belongs to the next plan and is not complete in this workspace.

## Requirements

- macOS 27 or later.
- Apple silicon only.
- Native arm64 Java Autogram/DSS helper.
- eID middleware and an arm64 PKCS#11 library for the selected token.
- I.CA SecureStore 8.3.1 or later when using an I.CA token.
- Network access to obtain and validate a qualified timestamp.

The PIN is entered in a secure field, cleared after use or dismissal, and sent to the helper only through standard input. It is not stored in preferences, process arguments, environment variables, or diagnostics.

## Setup

1. Install the required eID middleware and confirm that its selected PKCS#11 library is arm64.
2. For I.CA tokens, install I.CA SecureStore 8.3.1 or later.
3. Place the native arm64 Java Autogram/DSS helper in the app bundle at `Contents/Helpers/AutogramCLI-arm64`.
4. Ensure the machine can reach the qualified timestamp service used by the helper.
5. Open `Autogram.xcodeproj` in Xcode and select the `Autogram` scheme.

## Build and run

Build for Apple silicon:

```sh
xcodebuild -project Autogram.xcodeproj -scheme Autogram -destination 'platform=macOS,arch=arm64' build
```

Run from Xcode with the `Autogram` scheme. The application opens a native workspace where PDFs can be selected, inspected, and signed.

## Verification status and limitation

The project is configured for an arm64-only macOS 27 target. Automated verification covers the native unit and helper integration suites. A physical token signing session together with live qualified timestamp authority acceptance has not yet been verified.
