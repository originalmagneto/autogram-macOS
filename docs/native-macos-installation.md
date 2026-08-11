# Autogram macOS installation

This guide covers the native Apple silicon application. It uses SwiftUI, AppKit, and PDFKit for the interface and a bundled arm64 Autogram and DSS helper for signing and validation.

It is separate from the upstream JavaFX application and from the standalone CLI automation described in [macOS CLI automation](macos-cli-automation.md).

## Requirements

- Apple silicon Mac.
- macOS 27 or later.
- Compatible smart card, eID, or signing token.
- arm64 or universal PKCS#11 middleware.
- I.CA SecureStore 8.3.1 or later for I.CA cards.
- Network access for qualified timestamping, certificate status checks, and trust-list validation.
- Write access to the folder containing the source document.

Intel Macs, Intel-only PKCS#11 libraries, and Rosetta compatibility paths are not supported.

## Install a release build

1. Download the native macOS DMG from the fork release page.
2. Open the DMG.
3. Drag **Autogram macOS** into **Applications**.
4. Eject the DMG.
5. Open **Autogram macOS** from Applications.

The application bundle must keep its original internal structure. Do not replace the bundled helper or Java runtime with files from another Autogram installation.

The current public distribution workflow still requires Developer ID signing and Apple notarization. A locally built application uses an ad-hoc signature and macOS may require the usual local development approval.

## Install signing middleware

### I.CA cards

Install I.CA SecureStore 8.3.1 or later. This version provides a universal PKCS#11 library with an arm64 slice. Older Intel-only versions cannot be loaded by the native application.

### Slovak eID

Install the current Slovak eID client and verify that the selected `libPkcs11.dylib` contains an arm64 slice.

Autogram macOS checks middleware architecture before starting the signing helper. If the check fails, update or reinstall the middleware instead of installing Rosetta.

## First launch

1. Connect or insert the signing card.
2. Open Autogram macOS.
3. Open Settings and review the detected middleware.
4. Open a test PDF.
5. Confirm that the card and its signing certificates appear.
6. Select a default certificate if the card exposes more than one suitable certificate.

Only public token and certificate identifiers are remembered. The PIN is never stored.

## Finder Quick Action

The managed Quick Action directly signs one or more selected PDFs. It prompts for the signing card, certificate, and PIN, and writes a PAdES Baseline T output beside each source PDF. It does not invoke Terminal, the JavaFX interface, or the Autogram macOS workspace.

The Quick Action uses the same signing requirements shown in Settings. Install compatible arm64 or universal PKCS#11 middleware before using it. I.CA cards require SecureStore 8.3.1 or later. Slovak eID cards require the current eID client with an arm64 `libPkcs11.dylib`.

1. Open **Autogram macOS > Settings**.
2. Choose **Install Finder Quick Action**.
3. If macOS asks, enable it under **System Settings > General > Login Items & Extensions > Finder Extensions**.
4. Select one or more PDFs in Finder.
5. Control-click and choose **Quick Actions > Sign with Autogram macOS**.

Settings reports whether the installed action matches the version bundled with the app. If a managed action is already installed, Autogram macOS maintains it after an app update. Use Update when Settings reports a newer bundled version, Reinstall to replace the current action manually, or Remove to uninstall it. A removed action stays removed until you choose Install again.

## Output behavior

- Source files are never overwritten.
- The default PDF output is `<name>_signed.pdf` beside the source.
- Existing names are preserved and a collision-safe numbered name is created.
- ASiC-E output uses the `.asice` extension.
- A completed output becomes the active workspace document and is inspected again.
- When signatures exist, complete DSS validation runs automatically.

## Privacy and credentials

- PIN entry uses a native secure field.
- The PIN is sent to the bundled helper through standard input.
- The PIN is cleared after the operation and is not stored in settings, logs, arguments, or environment variables.
- Imported signature artwork is copied into the application's managed library.
- Diagnostics exclude private document content and credentials.
- The application accesses documents explicitly opened by the user or supplied by Finder.

## Troubleshooting

### No compatible driver is detected

Confirm that the middleware is installed and its PKCS#11 library contains an arm64 slice. For I.CA, install SecureStore 8.3.1 or later. Restart the application after changing middleware.

### No certificates are shown

Confirm that the card is inserted, visible in its middleware, and not being held by another application. Retry discovery. If the card exposes several certificates, choose a signing certificate and save it as the default for that card.

### The helper cannot start

Use the complete Autogram macOS application bundle. A copied Swift executable without its bundled helper, dependencies, and Java runtime cannot sign documents.

### The Finder action is missing

Confirm installation in Autogram Settings, enable the extension in System Settings, and relaunch Finder if its Quick Actions menu has not refreshed. If Settings reports an update, choose Update. Use Reinstall if the action is current but Finder still does not show it.

### Timestamp qualification fails

Check network access and the selected timestamp provider. A qualified timestamp requirement is enforced, so signing fails instead of silently producing a weaker result.

### Validation is indeterminate

The signature was discovered, but DSS could not obtain enough trust, revocation, timestamp, or certificate-chain evidence for a definitive result. Restore network access and use the validation refresh action. Indeterminate does not mean valid or invalid.

### A cloud file cannot be signed

Ensure the cloud provider has downloaded the complete file locally and that the containing folder is writable.

## Developer installation

For local build instructions see [native-macos/README.md](../native-macos/README.md). Release acceptance and notarization requirements are listed in the [native release checklist](native-macos-release-checklist.md).
