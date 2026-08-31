# Signed Preview and Metadata Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with verification after each observable change.

**Goal:** Show the signed PDF for PAdES and embedded XAdES PDF previews, expose detailed signature metadata, and render compact certificate and QTS details inside graphic signatures.

**Architecture:** Extend the existing signing result model with certificate and timestamp metadata, use the existing ASiC-E ZIP reader to extract the embedded PDF, and keep the current `SigningDoneView` preview/sidebar structure while replacing placeholder content with real data. Extend `VisibleSignatureStamper` with compact adaptive layout rendering that keeps the PNG dominant.

**Tech Stack:** Swift 6, SwiftUI, PDFKit, CoreText/CoreGraphics, existing AutogramKit signing engine and ASiC-E parser.

## Global Constraints

- Preserve existing PAdES and XAdES signing behavior.
- Do not add external dependencies.
- Keep graphic stamps compact and aspect-ratio aware.
- Use Slovak UI strings and English code comments.
- Do not use em dashes.

### Tasks

1. Add certificate and QTS display metadata to signing identities and result mapping.
2. Extend visual stamp data and renderer with compact certificate, time, and QTS lines.
3. Extract embedded XAdES PDF data for the completion preview.
4. Build detailed completion sidebar sections for PAdES and XAdES.
5. Add focused tests for extraction, metadata, and compact stamp layout.
6. Run the complete test suite and build/install the application.
