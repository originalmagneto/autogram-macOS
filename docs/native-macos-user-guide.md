# Autogram macOS user guide

## Open documents

Open files with **File > Open**, drag them into the application, or use the add button. PDF and ASiC-E files can share one workspace. The newest successfully added file becomes active automatically.

The sidebar shows every open item and its current state. Selecting an item changes the document preview and signing inspector.

## Review a PDF

PDFKit renders the document in the main area. Autogram performs a fast inspection when the file opens. If electronic signatures are detected, the right sidebar lists them and complete DSS validation begins.

Unsigned documents skip complete validation.

## Review existing signatures

The existing-signatures section shows:

- signer identity;
- signing time when available;
- signature format and baseline level;
- timestamp presence and qualification information;
- complete validation result.

Status meanings:

- **Valid**: DSS found sufficient evidence and no validation failure.
- **Invalid**: DSS found a cryptographic or validation failure.
- **Validation indeterminate**: the signature exists, but available evidence is insufficient for a definitive result.

Use validation refresh after network, revocation, timestamp, or trust-list services become available. After a new signature is added, the output is inspected and every signature is validated again.

## Review an ASiC-E container

Autogram lists the files contained in the container. Click an embedded PDF to preview it directly in the application. Other payloads remain listed even when no native preview is available. Existing XAdES or CAdES signatures are displayed in the same signature inspector.

When countersigning an existing ASiC-E container, Autogram preserves its signature family.

## Choose the signing format

- **Automatic** chooses PAdES for PDF and preserves an existing ASiC-E signature family.
- **PDF with PAdES** creates a signed PDF.
- **ASiC-E with XAdES** creates an `.asice` container.

PAdES Baseline T and qualified timestamping are the native preview defaults.

## Choose a card and certificate

Autogram discovers compatible connected middleware and asks the signing engine for certificates on the token. It can distinguish supported I.CA and eID paths without asking the user to type a driver identifier or certificate serial number.

If several suitable certificates are available, select one from the certificate card. The selection can be saved as the default for that card. Defaults use public token metadata and can be changed in Settings.

Insert or connect the card before signing. Enter the PIN only in the native secure sheet.

## Add a graphic signature to a PDF

A graphic signature is an optional visible appearance. The cryptographic electronic signature remains the authoritative signature.

1. Enable **Show signature on document**.
2. Choose an existing artwork item or import a transparent PNG or PDF.
3. The appearance is placed on the last page of a multi-page PDF, or page one for a one-page PDF.
4. Drag the card directly on the page.
5. Resize it with a corner handle.
6. Rotate it with the rotation handle.
7. Change the page in the inspector if required.

Artwork keeps its aspect ratio. A new document receives a fresh centered placement. Position, size, and rotation are not copied from the previous document.

The editable preview contains placeholder signing time and timestamp text. The final signed appearance uses actual signing information. After signing, the editable overlay is cleared and only the embedded appearance remains.

## Manage graphic artwork

Imported PNG and PDF artwork is copied into a private application library so it can be reused without depending on the original file path. Select an item to use it for the active PDF. Deleting an item removes only the managed copy, not the original source file.

Graphic appearance is disabled by default when the application opens.

## Qualified timestamps

Choose one of the provided timestamp services or add a custom TSA endpoint in Settings. The selected configuration is passed to the Autogram and DSS engine.

When a qualified timestamp is required, Autogram fails the operation if qualification cannot be proven. It does not silently downgrade the signature.

## Sign one or more files

1. Review the active document and existing signatures.
2. Choose the format and optional graphic appearance.
3. Confirm the detected certificate.
4. Start signing.
5. Enter the PIN in the secure sheet.

For multiple files, Autogram reports each result separately. A failure does not overwrite a source file. Successful outputs use collision-safe names beside their sources.

## Finder workflow

Install the managed Finder Quick Action from Settings. Select one or more PDFs in Finder and choose **Quick Actions > Sign PDFs Autogram**. The action prompts for the signing card, certificate, and PIN, then directly creates PAdES Baseline T output beside each source PDF without opening the Autogram macOS workspace or Terminal.

The repository also includes an older standalone CLI Quick Action with separate requirements and behavior. See [macOS CLI automation](macos-cli-automation.md) if you intentionally use that action instead of the Settings-managed action.

## Safety expectations

- Always inspect the selected document before entering a PIN.
- Treat indeterminate validation as unresolved, not as valid.
- Verify that qualified timestamping succeeded when it is required for the intended legal workflow.
- Keep card middleware current.
- Preserve the original and signed output according to the applicable records policy.
