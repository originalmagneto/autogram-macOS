# Task 5 report

## RED evidence

- The required `WorkspaceInspectionTests` command failed after the propagation test was added because `WorkspaceModel` had no visible appearance state or renderer dependencies.

## GREEN evidence

- The required workspace propagation test passes. It proves that a managed PNG and placement selected before certificate resolution produce one rendered PNG with page 2 and DSS rectangle 72/540/216/108 in the captured signing request.
- The native command for `AutogramTests` and `AutogramIntegrationTests` completed without test failures. It emitted only existing headermap and ad-hoc signing warnings.
- `git diff --check` passes.

## Self-review

- The inspector appears only for a selected PDF using Automatic or PDF with PAdES, and contains the required toggle, preview, import and removal actions, placement values, reset action, and direct-manipulation help text.
- Artwork is imported to managed storage. Signing renders the complete card only after certificate selection, uses the Java-supplied certificate display name, and passes no inferred qualification so the renderer shows `Certificate qualification unavailable` until Java supplies an authoritative value.
- One `Date` instance is used for the rendered card and every v2 appearance request. Missing, unreadable, unplaced, or non-PDF artwork stops before the signing coordinator begins.
- Preferences encode only managed asset ID, enabled state, and placement values. They do not encode original paths, rendered cards, PINs, or timestamp credentials.

## Fix round 1

- RED: the workspace test did not compile because `PDFDetailView` had no workspace input, `WorkspaceModel` had no card-content state, and `SigningCertificate` had no qualification field.
- `PDFDetailView` now binds the PDF overlay directly to `WorkspaceModel.visibleSignaturePlacement` and supplies the workspace card preview. Overlay edits update the exact placement later converted for signing.
- Certificate decoding now carries the optional Java `qualification` field into `SigningCertificate`. Final card rendering uses that authoritative value and retains the existing unavailable fallback when absent.
- GREEN: the focused `WorkspaceInspectionTests` command and the required `AutogramTests` plus `AutogramIntegrationTests` command completed without test failures.
- `git diff --check` passes.
