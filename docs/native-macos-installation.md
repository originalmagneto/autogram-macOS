# Native macOS Preview Installation

This guide is for the native macOS preview of Autogram. It is a separate Apple silicon application that uses a bundled Autogram machine helper built from this repository.

It is not the cross-platform JavaFX Autogram application, and it is not the existing command-line automation described in [macOS CLI automation](macos-cli-automation.md). The native preview provides a Finder Quick Action and a native document workspace without requiring Terminal use for normal signing.

## Requirements

- macOS 27 or later on Apple silicon.
- The native Autogram preview DMG from this repository's releases.
- Compatible eID middleware with an arm64 PKCS#11 library for the signing token.
- I.CA SecureStore 8.3.1 or later when using an I.CA token.
- Network access to the qualified timestamp authority used by the selected signing configuration.

At startup, the native application checks the selected PKCS#11 library architecture. Repair or update middleware if the library is not arm64. The preview does not support Intel Macs.

## Install the app

1. Open the downloaded `Autogram-native-preview.dmg`.
2. Drag `Autogram.app` to the `Applications` folder alias in the DMG window.
3. Eject the DMG after copying finishes.
4. Open Autogram from Applications and complete its initial setup.

The app bundle includes the native arm64 Java Autogram/DSS machine helper. Do not replace that helper with a separately downloaded executable.

## Install the Finder Quick Action

Finder Quick Action installation is explicit and is never performed automatically. In Autogram, open Settings and choose **Install Finder Quick Action**. macOS may ask for confirmation.

If Finder does not show the action, open **System Settings > General > Login Items & Extensions > Finder Extensions** and enable **Sign PDFs with Autogram**. Then select one or more PDFs in Finder, Control-click the selection, choose **Quick Actions**, and select **Sign PDFs with Autogram**.

The Quick Action sends the selected PDFs to the native application. It does not open Terminal or the cross-platform JavaFX interface. Multiple PDFs are accepted in one request.

## Signed files and privacy

For each source PDF, Autogram writes a new signed PDF beside the original. The default name is `<name>_signed.pdf`. The source PDF is not overwritten. If that name already exists, Autogram preserves it and creates a numbered collision-safe name.

Your PIN is entered in a secure field, cleared after signing or dismissal, and sent to the bundled helper through standard input. It is not saved in preferences, command arguments, environment variables, or diagnostics. The app accesses only files you choose or provide through Finder. Timestamping requires the network connection described above.

## Troubleshooting

**The app says the PKCS#11 library is incompatible.** Update or reinstall the token middleware and select its arm64 PKCS#11 library. For I.CA tokens, use I.CA SecureStore 8.3.1 or later.

**No certificate is available.** Confirm that the token is connected, unlocked, and visible in its middleware before opening Autogram. Reopen the app after installing or updating middleware.

**The Quick Action is missing from Finder.** Confirm it was installed in Autogram Settings, enable it under Finder Extensions in System Settings, and reopen Finder if macOS has not refreshed the menu.

**Timestamp signing fails.** Check network access to the configured qualified timestamp authority, then retry after service access is restored.

**A PDF cannot be signed.** Confirm that it is a readable PDF and that you can write to its folder. For cloud-synchronised files, allow the provider to download the file locally before signing.

## Current preview limitations

- A locally built preview does not create a Developer ID identity or a notarized artifact. Use the protected release workflow for signed and notarized distribution.
- Physical-token signing and live qualified timestamp authority acceptance have not yet been tested on a release candidate.

See the [native macOS release checklist](native-macos-release-checklist.md) for the remaining release acceptance gates.
