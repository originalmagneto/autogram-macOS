# Managed CLI Finder Quick Action

## Contract

Autogram macOS must install and maintain the direct Finder signing Quick Action from its Settings window. The installed action must sign selected PDF files through the bundled ARM64 Autogram helper, must not depend on a development checkout, and must remain current after application updates.

The contract is proven when:

1. Settings reports the signing prerequisites and their detected state.
2. The user can install, reinstall, and remove the direct signing Quick Action.
3. The installed workflow contains the required launcher scripts and no personal absolute path.
4. An installed managed workflow is replaced when its bundled version changes.
5. Removing the workflow disables automatic maintenance until the user installs it again.

## Product behavior

The Finder section in Settings describes that the action signs selected PDFs directly. It reports:

- availability of the bundled ARM64 Autogram helper;
- I.CA SecureStore 8.3.1 or newer when I.CA middleware is installed;
- availability and ARM64 compatibility of Slovak eID middleware;
- installation state of the managed Quick Action;
- whether the installed workflow is current or requires an update.

The primary action is **Install Finder Signing Action** when absent, **Update Finder Signing Action** when stale, and **Reinstall Finder Signing Action** when current. A separate destructive action removes it.

Installing the managed action replaces the previous `Sign PDFs Autogram.workflow` at the same user Services location. The unrelated action that only opens files in Autogram macOS is not installed or maintained by this feature.

## Packaging

The release application bundles a self-contained workflow template. The workflow contains the Quick Action shell entry point and machine CLI orchestration script. It resolves the signing helper from the installed Autogram macOS application and never references a source repository.

The build and release verification scripts check that:

- the workflow and its property lists are valid;
- its scripts are executable and pass shell syntax validation;
- no `/Users/` path, secret, PIN, certificate data, log, or development artifact is bundled;
- no Intel or Rosetta compatibility path is present.

## Versioning and maintenance

The bundled workflow has an application-owned version marker. The installer compares this marker with the installed copy.

After application launch, maintenance runs only when a managed workflow is already installed. If its version differs, the application atomically replaces it with the bundled version and refreshes macOS Services registration. If the workflow is absent, launch does nothing. This preserves an explicit user removal.

Installation and maintenance use a temporary sibling copy followed by replacement so an interrupted copy does not leave a partial workflow.

## Security

The PIN is accepted through the macOS secure dialog and passed to the machine helper through standard input. It is not written to a file, command argument, environment variable, preference, diagnostic message, or log.

The workflow may store temporary public certificate-list output during one invocation. Temporary data is removed when the action exits.

## Error handling

Settings shows a concise repair message when the bundled workflow is missing, installation fails, middleware is incompatible, or Services registration cannot be refreshed. Automatic maintenance failure does not block application launch. The failure remains visible in Settings and can be repaired with reinstall.

The Finder action preserves its current user-facing dialogs for card selection, certificate selection, PIN entry, signing success, and a redacted signing failure.

## Verification

Only focused evidence is required:

- installer state and version comparison tests;
- install, update, remove, and removed-state behavior using a temporary Services directory;
- shell syntax and existing machine request regression test;
- release bundle validation for workflow resources and forbidden paths.

No unrelated signing, PDF rendering, or UI test suite is required for this feature.
