# Native macOS architecture

## Design principle

Autogram macOS separates the native user experience from the cryptographic authority.

- SwiftUI provides application structure and state-driven controls.
- AppKit provides native document, window, Finder, and secure-input integration.
- PDFKit provides PDF rendering and coordinate conversion for visible signature placement.
- The Autogram Java engine and European Commission DSS perform signing, timestamping, certificate processing, trusted-list processing, and validation.

Cryptographic and eIDAS logic is not ported to Swift.

## Process model

```text
Finder or user-selected files
            |
            v
Native SwiftUI workspace
            |
            +--> PDFKit preview and placement overlay
            |
            +--> secure PIN sheet
            |
            v
Machine protocol over supervised process I/O
            |
            v
Bundled arm64 Autogram helper
            |
            +--> European Commission DSS
            +--> PKCS#11 middleware and card
            +--> qualified timestamp authority
            +--> validation trust and revocation services
```

The helper is a bundled component, not a separately discovered global CLI. This prevents the native application from accidentally invoking an older Autogram installation or an incompatible architecture.

## Apple silicon boundary

The target product is arm64 end to end:

- native application;
- helper launcher;
- bundled Java runtime;
- Java native dependencies;
- PKCS#11 middleware.

Universal middleware is accepted when it contains an arm64 slice. Intel-only libraries are rejected with repair guidance. Rosetta is not an installation or runtime requirement.

## Machine protocol

The native application communicates with the helper using the versioned protocol described in [machine-cli-protocol-v1.md](machine-cli-protocol-v1.md). Requests and responses use structured data so the UI does not parse human-oriented terminal text.

The protocol covers:

- diagnostics and helper capabilities;
- driver and certificate discovery;
- document inspection;
- complete validation;
- PDF and ASiC-E signing;
- visible PDF signature appearance;
- qualified timestamp configuration;
- structured errors and output paths.

Sensitive PIN data is supplied separately through standard input and is not encoded into process arguments.

## Document inspection and validation

Inspection is deliberately split into two phases:

1. Fast inspection identifies document type, container contents, and signature presence.
2. Complete DSS validation runs only when signatures are present or when the user explicitly requests it.

This keeps unsigned-document opening responsive while preserving authoritative validation for signed documents. Signed outputs always enter the inspection and validation flow again.

## Certificate discovery

The application detects known middleware paths and validates native architecture. The helper opens the PKCS#11 token and returns certificate metadata. User preferences may remember a default certificate using public driver, token, and certificate identifiers.

Private keys remain on the token. The application does not export them.

## Visible PDF signature appearance

The Swift layer renders the editable appearance preview and maps its PDFKit coordinates into a normalized protocol model. The helper and DSS embed the final visible appearance together with the cryptographic PAdES signature.

Placement belongs to one workspace document. Opening another document creates a fresh default placement. Existing embedded appearances are part of the PDF and are not reused as editable overlays.

Imported artwork is copied to application-managed storage. The renderer uses aspect-fit layout so transparent PNG and PDF artwork is not stretched.

## ASiC-E handling

ASiC-E is treated as a signed container, not as a PDF. The workspace lists payload entries and can preview an embedded PDF without modifying the container. Signing an existing container preserves its current XAdES or CAdES family. A new ASiC-E workflow can create XAdES output.

## Outputs

Output generation is collision-safe and never overwrites the source. The helper reports the actual output path, which the native application validates before declaring success. The output then replaces or augments the active workspace state and is inspected again.

## Trust boundaries and privacy

- The native UI owns user consent, file selection, display, and secure PIN entry.
- The helper owns signing and DSS validation operations.
- PKCS#11 middleware owns access to the private key.
- External TSA and validation services receive only protocol-required requests.
- PIN data is retained only for the active operation.
- Diagnostics must not contain PINs, private keys, timestamp credentials, or private document content.
- Source documents and imported originals are not deleted or overwritten.

## Packaging

The build script assembles an application bundle containing the Swift executable, helper, Java dependencies, and reduced arm64 runtime. Local builds use ad-hoc signing. Public distribution requires Developer ID signing, hardened runtime review, notarization, and the acceptance checks in [native-macos-release-checklist.md](native-macos-release-checklist.md).

## Upstream compatibility

The machine protocol, DSS work, and generally useful macOS integration are kept reviewable so they can be proposed to [slovensko-digital/autogram](https://github.com/slovensko-digital/autogram). Apple-specific presentation remains isolated from core signing behavior.
