# Task 1 Report: Managed CLI Finder Quick Action

## Outcome

Bundled the direct signing Finder Quick Action as `Sign PDFs Autogram.workflow` with managed-version marker `1` and the current safe launcher scripts.

## Changed files

- `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Info.plist`
- `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow`
- `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-quick-action.sh`
- `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-cli-sign.sh`
- `native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/managed-version`
- `native-macos/Autogram.xcodeproj/project.pbxproj`
- `scripts/native-macos/verify-native-release.sh`

## Verification

- Confirmed the initial native build lacked the managed workflow, as expected after adding the release verification requirement.
- `bash -n native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/*.sh` passed.
- `plutil -lint native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Info.plist` passed.
- `plutil -lint native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow` passed.
- `bash scripts/macos-automation/test_autogram-cli-sign.sh` passed.
- Structural checks confirmed marker `1`, executable bundled scripts, the required Xcode resource-phase reference, and no `/Users/`, `Intel`, or `Rosetta` text in the workflow.
- `git diff --check` passed.

## Self-review

The Automator Run Shell Script action resolves the managed workflow resources from the current user's Services directory and executes the bundled launcher with all incoming file arguments. The release verifier now requires the workflow, valid property lists, executable scripts, marker `1`, shell syntax, and prohibited-text checks.

## Remaining risk

The specified focused checks passed. A new native app or DMG was not built in this task, so the new resource has not been validated in a freshly assembled application bundle.

## Fix round 1

### Changes

- Changed the Automator Run Shell Script action to `inputMethod` `1`, which passes Finder items as arguments for the existing `"$@"` launcher contract.
- Added focused regression checks for argument delivery, the shell-script fake helper, and rejection of x86-only helper and Python overrides.
- Required an arm64 slice for Mach-O helper candidates and all Python candidates, and starts Python through `arch -arm64`. The explicit helper override still accepts a non-Mach-O script test double.
- Changed certificate lookup and signing failure exits from `0` to `1` after displaying an error alert. Cancellation paths remain `0`.
- Corrected the shell validation command by storing the path with spaces in a quoted variable.

### Exact verification commands and outputs

```bash
set -euo pipefail
workflow='native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents'
bash -n "$workflow"/Resources/*.sh
plutil -lint "$workflow/Info.plist"
plutil -lint "$workflow/document.wflow"
bash scripts/macos-automation/test_autogram-cli-sign.sh
[[ "$(plutil -extract 'actions.0.action.ActionParameters.inputMethod' raw "$workflow/document.wflow")" == "1" ]]
[[ "$(plutil -extract 'actions.0.action.ActionParameters.COMMAND_STRING' raw "$workflow/document.wflow")" == $'workflow_resources="$HOME/Library/Services/Sign PDFs Autogram.workflow/Contents/Resources"\nexec "${workflow_resources}/autogram-quick-action.sh" "$@"' ]]
```

Output:

```text
native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Info.plist: OK
native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow: OK
CLI Quick Action helper selection and machine request passed.
Task 1 focused workflow checks passed.
```

### Native resource build attempt

```bash
xcodebuild -project native-macos/Autogram.xcodeproj -scheme Autogram -configuration Release -sdk macosx -destination 'platform=macOS,arch=arm64' -derivedDataPath "$resource_build_dir/DerivedData" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
```

Output:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

The resource-only build was not completed because full Xcode is unavailable. No unrelated test suite was run.
