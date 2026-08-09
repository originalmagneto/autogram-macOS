# Autogram macOS App Identity

## Outcome

The native application is clearly distinguishable from the original Java Autogram and is installed as `/Applications/Autogram macOS.app`.

## Product identity

- Display name and application bundle name: `Autogram macOS`.
- Bundle identifier remains `digital.slovensko.autogram.native` so existing native preferences remain associated with the application.
- The original Java Autogram installation is not modified or replaced.

## Icon

- Native macOS rounded-square composition.
- Blue background with sufficient contrast in light and dark system appearances.
- White document, visible signing stroke, and a gold qualified seal with a checkmark.
- No words or letters inside the icon.
- The source is rendered into the standard macOS AppIcon asset sizes.

## Integration

- Finder, Dock, menu bar, application windows, and Open With display `Autogram macOS` and the new icon.
- The bundled Finder Quick Action opens the installed native application by its stable bundle identifier.
- PDF and ASiC-E document handling remains unchanged.

## Installation

- The verified ARM64 application is copied to `/Applications/Autogram macOS.app`.
- Installation replaces only an earlier native `/Applications/Autogram macOS.app` build when present.
- No application named `Autogram.app`, `Autogram Intel.app`, or another Java build is removed or overwritten.

## Acceptance

- `/Applications/Autogram macOS.app` exists and passes code-signature verification.
- Its executable, signing helper, and bundled Java runtime are ARM64.
- Finder and Dock show the selected icon and `Autogram macOS` name.
- Opening a PDF launches this native application and preserves signing-driver detection.
