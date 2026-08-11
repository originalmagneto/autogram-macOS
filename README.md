# Autogram macOS

Native electronic signing for Apple silicon Macs.

[Slovenska dokumentacia](README-SK.md) | [Installation](docs/native-macos-installation.md) | [User guide](docs/native-macos-user-guide.md) | [Architecture](docs/native-macos-architecture.md)

Autogram macOS is a SwiftUI and AppKit desktop application for reviewing, signing, and validating electronic documents. It combines a native macOS workspace with the proven Java Autogram and European Commission DSS signing engine.

The application is designed for legal, business, and public-sector workflows where the user must understand what is being signed, which certificate is used, whether qualified timestamping succeeded, and which signatures already exist in the document.

> Development status: active preview. The native application currently targets macOS 27 or later and Apple silicon only. Public release artifacts still require Developer ID signing and notarization.

## Highlights

- Native SwiftUI document workspace with AppKit and PDFKit integration.
- Apple silicon architecture from the application through the bundled Java runtime and signing helper.
- PDF signing with PAdES Baseline T and a qualified timestamp requirement.
- ASiC-E and XAdES workflows, including inspection of existing containers.
- Existing signature detection and complete DSS validation.
- Revalidation after countersigning, with truthful valid, invalid, and indeterminate states.
- Automatic card and certificate discovery for supported PKCS#11 middleware.
- Remembered default certificate based only on public token metadata.
- Secure PIN entry that is never stored in preferences or command arguments.
- Reusable PNG and PDF graphic signature artwork library.
- Direct on-page placement, drag, resize, rotation, and page selection.
- Batch intake and signing of multiple selected documents.
- Finder Quick Action integration without Terminal interaction.
- Qualified timestamp provider selection and custom TSA endpoints.

## Native signing workflow

1. Open or drag one or more PDF or ASiC-E files into Autogram macOS.
2. The newest file becomes active automatically after it is loaded.
3. Autogram inspects the document and lists existing electronic signatures.
4. Complete DSS validation runs only when electronic signatures are present.
5. The application detects compatible connected signing middleware and certificates.
6. Choose the signing format, certificate, timestamp configuration, and optional graphic appearance.
7. Enter the PIN in the native secure sheet.
8. Autogram creates a new collision-safe output beside the source file.
9. The signed result becomes active and every electronic signature is validated again.

The original document is never overwritten.

## Supported document workflows

| Input or output | Current native workflow |
| --- | --- |
| PDF | Preview, inspect, validate, and sign with PAdES Baseline T |
| Existing signed PDF | Display existing signatures, countersign, and revalidate all signatures |
| ASiC-E `.asice` | Inspect container contents, preview embedded PDFs, and preserve the existing XAdES or CAdES signature family |
| New ASiC-E output | Create an ASiC-E container with XAdES when selected |
| Multiple files | Add or open together and process in one workspace |

The repository also retains the upstream JavaFX application, HTTP API, machine CLI, eForm support, and automation scripts inherited from [Slovensko.Digital Autogram](https://github.com/slovensko-digital/autogram).

## Existing signatures and validation

Autogram macOS separates fast inspection from authoritative validation:

- Fast inspection discovers whether signatures exist and makes document metadata available quickly.
- Complete validation is delegated to the bundled Autogram and DSS engine.
- Unsigned documents do not trigger unnecessary complete validation.
- Signed outputs are inspected and validated again automatically.
- `Valid` means the available DSS evidence supports the signature.
- `Invalid` means validation found a signature failure.
- `Validation indeterminate` means the signature was found, but available trust, revocation, timestamp, or certificate-chain evidence was insufficient for a definitive result.
- The user can request validation again when the required online evidence later becomes available.

Autogram macOS does not reimplement cryptography or eIDAS validation in Swift. The native layer supervises the signing engine and presents its results.

## Graphic signatures

A graphic signature is an optional visible appearance attached to the cryptographic PDF signature. It is not a substitute for the electronic signature.

- Import transparent PNG artwork or a selected page from a PDF.
- Imported artwork is copied into a private reusable application library.
- Artwork keeps its original aspect ratio.
- Choosing artwork explicitly enables a fresh placement for the active document.
- The initial placement is centered on the last page, or the first page for a one-page PDF.
- Drag, resize, or rotate the card directly on the PDF preview.
- Change the target page from the signing inspector.
- The placement and rotation are never reused automatically for another document.
- The preview uses placeholder timing text. The signed output contains the real signing time and timestamp status.
- After signing, the editable overlay is cleared so it cannot overlap the embedded appearance.

## Cards, certificates, and middleware

The native application discovers supported PKCS#11 middleware and asks the signing engine for the certificates available on the connected token.

Supported and tested development paths include:

- I.CA SecureStore 8.3.1 or later.
- Slovak eID middleware with an arm64-capable PKCS#11 library.
- Other PKCS#11 tokens when their library and token behavior are compatible with Autogram.

The application is arm64-only. Intel-only PKCS#11 libraries and Rosetta compatibility paths are intentionally unsupported.

## Requirements

### End users

- Apple silicon Mac.
- macOS 27 or later.
- Compatible signing card or token.
- arm64 or universal PKCS#11 middleware.
- I.CA SecureStore 8.3.1 or later for I.CA cards.
- Network access for qualified timestamping and online signature validation.
- Write access to the source document folder.

### Developers

- Xcode with the macOS 27 SDK.
- Apple silicon build machine.
- JDK 25 with JavaFX for the Autogram helper build.
- Maven through the included wrapper.

Liberica JDK with JavaFX is the recommended Java distribution for local development.

## Install the native application

Release installation and Finder integration are described in the [native macOS installation guide](docs/native-macos-installation.md).

For a local development build:

```sh
export AUTOGRAM_JAVA_HOME="/path/to/arm64-jdk-with-javafx"
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
scripts/native-macos/build-native-app.sh
scripts/native-macos/sign-native-app.sh
open "build/native/Autogram macOS.app"
```

The build script creates `build/native/Autogram macOS.app` with:

- the native Swift application;
- the arm64 Autogram machine helper;
- the Java dependencies used by Autogram and DSS;
- a reduced arm64 Java runtime.

The local signing script applies an ad-hoc signature. It does not provide Apple notarization.

## Finder Quick Action

The managed Finder Quick Action directly signs one or more selected PDFs. It prompts for the signing card, certificate, and PIN, then creates PAdES Baseline T output beside each source PDF. It does not open the Autogram macOS workspace or require Terminal interaction.

Compatible arm64 or universal PKCS#11 middleware is required. I.CA cards require SecureStore 8.3.1 or later, and Slovak eID cards require the current eID client with an arm64 `libPkcs11.dylib`.

1. Open Autogram macOS Settings.
2. Choose **Install Finder Quick Action**.
3. If required, enable the action under **System Settings > General > Login Items & Extensions > Finder Extensions**.
4. Select one or more supported files in Finder.
5. Control-click one or more PDFs and choose **Quick Actions > Sign PDFs Autogram**.

Settings shows whether the bundled action is current. A previously installed managed action is updated after an app update, and Settings also offers Update, Reinstall, and Remove controls. Removing it prevents automatic reinstallation until you choose Install again.

The PIN remains only in script memory and passes through standard input. It is never persisted or placed in arguments, environment variables, or logs. Detailed setup and troubleshooting are in the [installation guide](docs/native-macos-installation.md).

The repository also includes the older standalone CLI Quick Action. Its separate requirements and installation are documented in [macOS CLI automation](docs/macos-cli-automation.md).

## Build and test

Run the native unit suite:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -destination 'platform=macOS' \
  -only-testing:AutogramTests \
  test
```

Build the upstream Java application and helper:

```sh
./mvnw -Psystem-jdk test
./mvnw -Psystem-jdk -DskipTests package
```

## Security and privacy

- PIN values are held only for the active operation and cleared after use.
- PIN values are sent to the bundled helper through standard input.
- PINs are not stored in preferences, logs, process arguments, or environment variables.
- Timestamp credentials are not stored in plaintext preferences.
- Diagnostics are designed to exclude secrets and private document content.
- Source documents are not overwritten.
- Managed graphic artwork is stored inside application support, not by referencing the original private path.
- PKCS#11 libraries are checked for arm64 compatibility before use.

Review [native macOS architecture](docs/native-macos-architecture.md) for the trust boundaries and process model.

## Documentation

- [Native macOS installation](docs/native-macos-installation.md)
- [Native macOS user guide](docs/native-macos-user-guide.md)
- [Native macOS architecture](docs/native-macos-architecture.md)
- [Native release checklist](docs/native-macos-release-checklist.md)
- [Machine CLI protocol](docs/machine-cli-protocol-v1.md)
- [macOS CLI and standalone Finder Quick Action](docs/macos-cli-automation.md)
- [Batch signing API](docs/batch-sign-api.md)
- [Batch signing GUI](docs/batch-sign-gui.md)
- [Upstream porting notes](PORTING.md)
- [Development plan](PLAN.md)

## Upstream relationship

This fork keeps the upstream Autogram and DSS signing engine as the cryptographic authority. Native macOS work is intentionally separated into the Swift application, machine protocol, Finder integration, and platform packaging so generally useful changes can be proposed upstream without coupling cryptographic behavior to Apple frameworks.

Upstream project: [slovensko-digital/autogram](https://github.com/slovensko-digital/autogram)

## License

Autogram is distributed under the EUPL v1.2. The project was originally derived from the Octosign White Label project by Jakub Duras, licensed under MIT and distributed here with the author's permission.

Commercial and non-commercial use is permitted subject to the EUPL conditions, including publication of covered modifications and preservation of applicable copyright notices.
