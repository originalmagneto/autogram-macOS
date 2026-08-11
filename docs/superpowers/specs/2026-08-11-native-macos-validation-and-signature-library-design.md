# Autogram macOS Validation and Graphic Signature Library Design

## Goal

After signing, Autogram macOS must automatically validate every signature in the resulting document. A graphic signature must never be active merely because artwork was used previously. Imported PNG and PDF artwork must remain available in a small internal library for deliberate reuse.

## Contract

The change is complete when:

1. A successfully signed output becomes the active document and automatically receives complete DSS validation. Its signature cards leave the provisional orange state when DSS can determine validity.
2. `Verify Again` remains available when complete validation fails or returns an incomplete result, together with a safe reason.
3. Opening any PDF starts with `Show signature on document` disabled, even when artwork and placement were saved previously.
4. A visible signature overlay appears only after the user deliberately chooses stored artwork or imports new artwork for the active document.
5. After a successful signature, visible-signature composition is disabled before the signed output becomes active. Existing appearance graphics embedded in the PDF remain document content and do not create a new overlay.
6. Every successfully imported PNG or supported PDF artwork is stored in an internal library. The user can select or delete stored artwork without browsing for the original file again.

## Root Causes to Address

### Provisional validation after signing

The signed output is re-inspected, but the complete DSS validation lifecycle must be explicitly attached to the new active descriptor. A stale validation task or state from the source document must not suppress or overwrite validation of the output.

### Persisted activation state

Visible-signature preferences currently persist both the selected asset and the enabled flag. Persisting activation causes a new document to display a placement overlay immediately. Artwork may persist, but activation is session and document intent, not a user default.

### Reused placement on signed output

The signing workspace retains visible-signature state while replacing the source with the signed output. The new output therefore receives another editable overlay at the old placement, directly above the appearance already embedded by DSS.

## Design

### Validation lifecycle

The completed-signing path will:

1. Finalize the output.
2. Make the output descriptor active.
3. Reset validation progress for that descriptor.
4. Run fast inspection.
5. Start complete DSS validation for the same descriptor generation.

Descriptor identity and generation checks will reject stale results. Complete validation will update every signature card together. A request failure or missing complete result will produce `.incomplete(reason)`, which is the only state that exposes `Verify Again`.

### Visible-signature activation

`visibleSignatureEnabled` will initialize as `false` for every workspace and reset to `false` whenever the active document changes because signing produced a new output. Stored artwork may remain selected in the library, but selection alone must not render an overlay.

The user activates composition by choosing artwork from the library or importing new artwork. That action enables the visible signature and initializes a placement on the last page, or page one for a single-page PDF. Turning the switch off removes the overlay without deleting artwork from the library.

### Artwork library

The existing managed signature asset storage will become the source of a minimal library model. It will expose stored asset metadata without reading arbitrary external paths. Importing PNG or supported PDF artwork copies the normalized asset into managed storage and adds it to the library.

The inspector will show:

- stored artwork thumbnails or compact rows;
- selection by one click;
- an import action;
- deletion of a selected stored asset.

Deleting an asset removes only the managed copy. If it is active, visible-signature composition is disabled and its overlay is removed. The library will not store PINs, certificate identifiers, timestamps, or document-specific placements.

### Existing PDF appearances

Autogram will not attempt to interpret or reconstruct existing visible signature appearances as editable overlays. PDFKit displays them as ordinary signed document content. Only the current unsaved composition receives selection handles.

## Error Handling

- A failed artwork import leaves the library and current composition unchanged and presents the existing safe import error.
- A failed library deletion leaves the item available and reports the failure.
- A failed complete DSS validation preserves inspected signatures, marks validation incomplete, shows the reason, and offers `Verify Again`.
- Switching documents or completing a signature cancels or invalidates stale preview and validation work through descriptor generation checks.

## Verification

Use the smallest proofs that close the contract:

1. A workspace test proving a signed output automatically starts complete validation and reaches the returned result.
2. A preferences or workspace test proving saved artwork does not enable a visible signature in a newly opened workspace.
3. A workspace test proving successful signing disables the composition overlay before activating the output.
4. An asset-store test proving imported assets can be listed, selected, and deleted.
5. The existing native test target and Debug build.
6. A live check with a co-signed PDF proving valid signatures remain green after signing and no duplicate editable overlay appears.

No broader test matrix, profile system, saved placement presets, or automatic artwork activation is part of this change.
