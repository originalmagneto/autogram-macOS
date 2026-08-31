# Signature Sidebar and Action Nomenclature

## Goal

Make the signing action and existing-signature summary unambiguous when a document already contains one or more electronic signatures.

## Approved behavior

The primary action label is contextual:

- No existing signatures: `Podpísať KEP`
- One or more existing signatures: `Pridať podpis`
- While signing: `Podpisujem…` or the current signing status text

When existing signatures are present, the helper text is:

`Pridá sa ďalší podpis k existujúcim podpisom v dokumente.`

## Existing signatures panel

The panel title includes the count:

`Podpisy v dokumente · N`

Each signature is rendered separately. A signature entry shows:

- signer display name,
- signature format and level when available,
- QTS marker when present,
- validation state: `Platný`, `Neplatný`, `Dočasný`, or `Neoverené`,
- signing date and time when available,
- validation detail as secondary text.

Validation detail is shown in a compact expandable area to keep the sidebar usable with multiple signatures. Entries must not be merged into one summary string.

## Data flow

`SigningSessionStore.existingSignatures` remains the source of truth. The view derives the count and action label from that array. `DocumentSignatureInfo` already supplies signer, format, signing time, QTS, state, and detail fields.

## Scope

Update the signing prepare view and its signature row presentation. Do not change signature inspection, signing, ASiC-E parsing, or provider APIs.

## Verification

Add view-model or presentation tests for zero, one, and multiple signatures where the existing test structure permits. Build the app and inspect the signing prepare screen with both unsigned and signed input states.
