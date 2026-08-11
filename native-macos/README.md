# Autogram macOS developer workspace

This directory contains the native SwiftUI application. It uses AppKit for macOS integration, PDFKit for document preview and visible-signature placement, and the bundled Autogram and DSS helper for cryptographic operations.

Start with the root [README](../README.md), [installation guide](../docs/native-macos-installation.md), [user guide](../docs/native-macos-user-guide.md), and [architecture](../docs/native-macos-architecture.md).

## Target

- macOS 27 or later.
- Apple silicon only.
- Xcode with the macOS 27 SDK.
- JDK 25 with JavaFX for helper packaging.
- arm64 or universal PKCS#11 middleware.

The native target does not use Rosetta or an Intel helper fallback.

## Project structure

- `Autogram/`: application sources and resources.
- `AutogramTests/`: native unit and integration-boundary tests.
- `Autogram.xcodeproj/`: Xcode project and schemes.
- `Package.swift`: package metadata used by supporting workflows.
- `resources/`: application resources included by the native build.

Important source areas:

- `Core/Models`: workspace and preference models.
- `Features/Workspace`: document intake, selection, signing state, and results.
- `Infrastructure/Machine`: machine-protocol transport and decoding.
- `Infrastructure/PDF`: PDFKit preview and placement overlay.
- `Infrastructure/SignatureAssets`: managed artwork library and visible appearance rendering.

## Build the complete app bundle

From the repository root:

```sh
export AUTOGRAM_JAVA_HOME="/path/to/arm64-jdk-with-javafx"
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
scripts/native-macos/build-native-app.sh
scripts/native-macos/sign-native-app.sh
open "build/native/Autogram macOS.app"
```

The resulting bundle includes the Swift application, arm64 machine helper, Java dependencies, and reduced Java runtime. The local signature is ad-hoc and is not a notarized public release.

## Build the Xcode target

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Running only the Xcode target may not provide a packaged helper. Use the complete bundle build for signing acceptance tests.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -destination 'platform=macOS' \
  -only-testing:AutogramTests \
  test
```

Keep tests focused on observable protocol, state, geometry, output, and security behavior. Physical-card and live timestamp acceptance remain explicit release checks rather than mocked claims.

## Security constraints

- Never place PINs in arguments, environment variables, preferences, or logs.
- Never bundle private documents or user-specific paths.
- Validate every selected PKCS#11 library for arm64 support.
- Do not overwrite source documents.
- Treat the Autogram and DSS helper as the signing and validation authority.
- Keep `AGENTS.md` and `CLAUDE.md` identical.

## Finder integration

The application installs its Finder Quick Action explicitly from Settings. The action forwards selected file URLs to the installed native application. It must not depend on a global Autogram CLI or another app bundle.

## Release

Follow [native-macos-release-checklist.md](../docs/native-macos-release-checklist.md) for architecture checks, helper packaging, middleware acceptance, Developer ID signing, notarization, and clean-machine verification.
