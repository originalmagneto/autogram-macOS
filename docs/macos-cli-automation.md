# Autogram CLI Automation on macOS

Autogram supports CLI mode via `--cli` and can be automated from Finder through an Automator Quick Action. This document describes the macOS integration in this fork. It is not a macOS Shortcuts workflow.

## What was prepared

- `scripts/macos-automation/autogram-cli-sign.sh`
- `scripts/macos-automation/autogram-quick-action.sh`
- `scripts/macos-automation/autogram-finder-selection.sh`

## Requirements

- macOS with Finder and Automator.
- A CLI-capable Autogram application. The scripts do not install Autogram.
- The signing token or card, its PKCS#11 driver, and the PIN.
- Network access to the qualified timestamp service when PAdES Baseline T is required.
- Rosetta and an Intel Autogram build on Apple Silicon when the PKCS#11 driver is Intel-only.

The Quick Action does not open the Autogram GUI or a Terminal window. It uses macOS dialogs for certificate store selection, certificate selection, and PIN entry, then runs the CLI in the background.

## 1) Make scripts executable

```bash
chmod +x scripts/macos-automation/*.sh
```

## 2) Quick Action (right click in Finder)

1. Open Automator and create a new **Quick Action**.
2. Set:
   - Workflow receives current: `files or folders`
   - In: `Finder`
3. Add **Run Shell Script** action.
4. Set:
   - Shell: `/bin/bash`
   - Pass input: `as arguments`
5. Script body:

```bash
REPO_DIR="/path/to/autogram-macOS"
"$REPO_DIR/scripts/macos-automation/autogram-quick-action.sh" "$@"
```

When triggered from Finder, it uses macOS dialogs for the certificate store, certificate and PIN, then runs Autogram CLI in the background. No Autogram window or Terminal window is opened. Select one or more PDF files in Finder to process them as a batch.

The Quick Action always configures:

- PAdES for PDF files.
- A qualified timestamp from `http://timestamp.sectigo.com/qualified`.
- The selected certificate storage.

When multiple PDF files are selected, the same CLI configuration is applied to each file. After signing, each result is saved beside the original as `<name>_signed.pdf`, with numbered variants if that filename already exists.

## 3) Finder automation (current selection)

Run this script whenever Finder already has items selected:

```bash
REPO_DIR="/path/to/autogram-macOS"
"$REPO_DIR/scripts/macos-automation/autogram-finder-selection.sh"
```

You can bind it in your preferred launcher (Shortcuts, Alfred, Raycast, etc.).

## Notes

- Default binary lookup:
  - `/Applications/Autogram.app/Contents/MacOS/AutogramApp`
  - `$HOME/Applications/Autogram.app/Contents/MacOS/AutogramApp`
  - local build: `target/app-image/Autogram.app/Contents/MacOS/AutogramApp`
- Override binary location with `AUTOGRAM_BIN=/custom/path/AutogramApp`.
- On Apple Silicon, the I.CA SecureStore 8.1 driver currently installed on this Mac is Intel-only. The launcher detects this and uses an Intel Autogram build through Rosetta when available.
- Put the Intel GUI build at `$HOME/Applications/Autogram Intel GUI.app`. The Quick Action also recognizes `$HOME/Applications/Autogram Intel.app` and `/Applications/Autogram Intel.app`.
- For the manual CLI script, set `AUTOGRAM_INTEL_BIN=/custom/path/Intel/AutogramApp` when needed.
- The official Autogram release publishes separate `macos.pkg` and `macos-intel.pkg` packages. The Intel package is required for an Intel-only PKCS#11 driver.
- `autogram-cli-sign.sh` remains available for manual CLI use and may ask for driver, key, PIN or password in Terminal.
- The Finder Quick Action uses `autogram-quick-action.sh`, which drives the CLI path without opening a terminal.
- The CLI fork supports `--list-keys`, `--key` and `--pin-stdin` for this Quick Action.
- The Intel Quick Action validates the certificate output and the resulting PDF because the Intel jpackage launcher can return a signal after PKCS#11 cleanup under Rosetta.
- A qualified timestamp is a property of the TSA response. For legal use, verify the TSA service in the EU Trusted List.
- You can pass options to signer directly, e.g.:

```bash
scripts/macos-automation/autogram-cli-sign.sh --driver eid --pdfa "/path/to/file.pdf"
```

For a deterministic I.CA workflow, pass the driver explicitly:

```bash
scripts/macos-automation/autogram-cli-sign.sh --driver secure_store "/path/to/file.pdf"
```

## Project Findings and Troubleshooting

This section records the findings from the macOS CLI and Finder Quick Action integration. Keep it updated when the signing path or packaged application changes.

### 2026-08-06: I.CA SecureStore on Apple Silicon

- The installed I.CA SecureStore PKCS#11 library is Intel-only: `/usr/local/lib/pkcs11/libICASecureStorePkcs11.dylib`.
- An arm64 Java process cannot load that library. The characteristic error contains `incompatible architecture (have 'x86_64', need 'arm64')`.
- The working configuration is the Intel Autogram build executed through Rosetta. The Quick Action detects this requirement and selects `$HOME/Applications/Autogram Intel GUI.app`.
- Do not replace the Intel-only driver with an arm64 assumption. First check both the application and PKCS#11 library architecture with `lipo -verify_arch`.

### 2026-08-06: Intel CLI exit status under Rosetta

- After SunPKCS#11 is loaded, the Intel jpackage runtime can abort during native cleanup. The process may return status `137` even when the signature and output file were completed.
- `AppStarter` flushes CLI output and terminates the short-lived Intel process after the signing work has finished. This avoids the native cleanup crash.
- The Quick Action must therefore verify the output artifact instead of treating a non-zero process status as conclusive failure.
- A successful PDF must be a real PDF: it starts with `%PDF-` and contains `%%EOF` near the end. A file starting with `PK` is an ASiC ZIP and must not be accepted as a PDF.

### 2026-08-06: PAdES Baseline T routing

- `SigningJob.getParametersForFile` originally routed only `PAdES_BASELINE_B` to `SigningParameters.buildForPDF`.
- `PAdES_BASELINE_T` fell through to the ASiC XAdES fallback, producing an ASiC ZIP with a `.pdf` filename when the Quick Action requested a timestamped PDF.
- `UserSettings.shouldSignPDFAsPades()` also recognized only `PAdES_BASELINE_B`, which could select the wrong output path for Baseline T.
- The source fix must cover both places:
  - route `PAdES_BASELINE_T` to `buildForPDF`;
  - treat `PAdES_BASELINE_T` as PAdES in `shouldSignPDFAsPades()`.
- The Quick Action passes `--pdf-level PAdES_BASELINE_T` and `--tsa-server http://timestamp.sectigo.com/qualified`.
- Regression tests are in `SigningJobTests`: one checks the PAdES job form and one checks the output classification in `UserSettings`.

### 2026-08-06: Packaged JAR class dependencies

- Java enum `switch` statements generate synthetic companion classes. For `SigningJob`, the enum mapping is stored in `SigningJob$1.class`.
- Updating only `SigningJob.class` inside an already packaged `autogram.jar` is insufficient. The old `SigningJob$1.class` can continue routing `PAdES_BASELINE_T` to ASiC even though the source and main class look fixed.
- When patching a packaged application, copy every changed class and its generated companion classes, then re-sign the app. At minimum, verify:

```bash
jar tf "$HOME/Applications/Autogram Intel GUI.app/Contents/app/autogram.jar" \
  | grep -E 'SigningJob(\$1)?\.class'

codesign --verify --deep --strict "$HOME/Applications/Autogram Intel GUI.app"
```

- Use `javap` on the packaged `SigningJob$1` to confirm that `PAdES_BASELINE_T` is present in the enum mapping. Source tests alone do not prove that the packaged JAR was updated correctly.

### Quick Action implementation rules

- Automator provides a restricted `PATH`. Do not depend on developer tools such as `rg` in the Quick Action. Use system paths for tools such as `/usr/bin/grep`, `/usr/bin/head` and `/usr/bin/tail`.
- Keep certificate store, certificate selection and PIN entry in macOS dialogs. The signing operation itself must remain CLI-based and must not open the Autogram GUI or Terminal UI.
- For multiple selected files, process each PDF separately and create a distinct target using `<name>_signed.pdf`, followed by numbered variants when necessary.
- If the output validation fails, show the captured CLI details and exit cleanly after the alert. Returning another non-zero status causes Automator to display a second empty generic error dialog.
- Never report success only from the CLI status. Confirm the expected output path and inspect the file header when diagnosing a signing report.

### Verification checklist before handing over a change

1. Run the focused regression tests for PAdES Baseline T.
2. Run the full Maven test suite with `./mvnw -q -Psystem-jdk test`.
3. Run `bash -n` for both macOS automation scripts.
4. Validate the installed workflow with `plutil -lint`.
5. Confirm all changed main and synthetic classes are in the packaged JAR.
6. Re-sign and verify the macOS app with `codesign --verify --deep --strict`.
7. Test with a fresh source PDF. If prior outputs exist, expect a numbered output such as `_signed (2).pdf`.
8. Do not use an earlier output that begins with `PK`; it is an ASiC container despite the `.pdf` extension.
