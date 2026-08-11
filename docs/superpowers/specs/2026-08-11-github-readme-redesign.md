# GitHub README Redesign

## Contract

The root `README.md` presents Autogram macOS as a polished native product and remains a reliable entry point for installation, use, development, security, documentation, upstream attribution, and licensing.

## Structure

1. Centered product hero with the existing project icon, product name, concise positioning, and status badges.
2. Compact navigation links for Slovak documentation, installation, user guide, architecture, and upstream.
3. Visible preview notice stating macOS 27+, Apple silicon, and the current signing and notarization limitation.
4. Feature overview table covering native workspace, PAdES, ASiC-E and XAdES, DSS validation, graphic signatures, card discovery, qualified timestamps, batch workflows, and Finder signing.
5. Small Mermaid workflow showing document intake, inspection, optional validation, certificate selection, secure PIN entry, signing, timestamping, and output revalidation.
6. Focused product sections for document formats, signature validation, graphic signatures, cards and middleware, Finder Quick Action, requirements, installation, security, development, documentation, upstream relationship, and license.
7. Build and test commands placed in collapsible details so the product overview remains readable.

## Visual rules

- Use GitHub-native Markdown and HTML supported by GitHub.
- Use badges only for facts already established by the repository.
- Do not add obsolete application screenshots.
- Do not use remote marketing images or tracking assets.
- Do not add personal paths, private documents, secrets, or client information.
- Do not use em dashes.
- Keep headings scannable and avoid repeating the same requirement in multiple sections unless needed for safety.

## Required facts

- Autogram macOS is an active preview targeting macOS 27 or later on Apple silicon.
- The SwiftUI and AppKit frontend supervises the existing Autogram and European Commission DSS engine.
- Supported workflows include PAdES Baseline T and ASiC-E with XAdES, with qualified timestamps where required.
- I.CA requires SecureStore 8.3.1 or later. Slovak eID requires current arm64-capable middleware.
- The Finder Quick Action directly signs selected PDFs and is installed and maintained from Settings.
- PIN values are not persisted or placed in arguments, environment variables, or logs.
- Public releases still require Developer ID signing and notarization.
- Upstream attribution and EUPL v1.2 license information remain visible.

## Proof

- Every local link resolves to an existing repository file.
- Markdown contains no personal absolute path, em dash, obsolete screenshot reference, or secret-like value.
- The final branch is fast-forwarded into `main`, and local `main` matches `origin/main` after push.
