# Chevron7 Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the product from Autogram macOS to Chevron7 in the repository and on this Mac, while every Autogram dependency (engine, AVM relay, ditec contract, asice UTI) keeps working and a script proves it.

**Architecture:** Two phases. Phase A changes only the repository, on branch `rename/chevron7`, and never touches the installed system: a boundary guard first, then renames in groups whose names must match each other at install time, then licensing, docs and the package folder. Phase B is operational and destructive, so each task starts with the user's explicit yes: tear down the old install, copy the data folders, build and register the new bundle, verify, then merge and rename the GitHub repository. Swift reads every OS-visible name from one new module, `Chevron7Identity`, so a later prefix change is one file in Swift plus the literals the scripts repeat.

**Tech Stack:** Swift 6 / SwiftPM (macOS 27), bash, launchd, pluginkit, lsregister, Safari Web Extension (MV3 JavaScript), `gh`.

**Spec:** `Autogram/docs/superpowers/specs/2026-09-22-chevron7-rename-design.md`

## Global Constraints

- **Gate:** no task runs until Task 0 is checked off by the user. `BUNDLE_ID = app.slovensko.chevron7` is the reverse of `chevron7.slovensko.app`, a subdomain of `slovensko.app`, which the user owns (decided 2026-09-22; `chevron7.app` and `chevron7.eu` were unregistered that day and knowingly not bought).
- Product name: `Chevron7`, one word, no space, everywhere a person reads it.
- `BUNDLE_ID = app.slovensko.chevron7`. The subdomain already names the product, so the app's bundle id is the reversed domain itself, with no second `Chevron7` segment, and every other name hangs below it. App `app.slovensko.chevron7`; appex `app.slovensko.chevron7.WebExtension`; Mach service and LaunchAgent label `app.slovensko.chevron7.webbridge`; URL scheme `chevron7`; URL type name `app.slovensko.chevron7.ezzk`.
- Installed bundle `/Applications/Chevron7.app`; executable `Chevron7`; appex folder `Chevron7WebExtension.appex` with executable `Chevron7WebExtension` and principal class `Chevron7WebExtensionHandler`.
- Data root: `~/Library/Application Support/Chevron7` holds everything that today lives in `~/Library/Application Support/Autogram` (Evidence, Output, Templates, VisionBank, Signatures) and in `~/Library/Application Support/Autogram macOS` (Visual Signatures). Cache root `~/Library/Caches/Chevron7`.
- Swift modules: `AutogramApp` → `Chevron7App`, `AutogramKit` → `Chevron7Kit`, `AutogramWebBridge` → `Chevron7WebBridge`, `AutogramWebExtensionHandler` → `Chevron7WebExtensionHandler`, `autogram-webbridge-agent` → `chevron7-webbridge-agent`, tests `AutogramAppTests` → `Chevron7AppTests`, `AutogramKitTests` → `Chevron7KitTests`, package and executable product `Autogram` → `Chevron7`. New module `Chevron7Identity`.
- **Mobile signing is the one path that must survive unchanged.** The Autogram v mobile iPhone app opens QR links only for `autogram.slovensko.digital`, so the relay URL, the QR link host, the `X-Encryption-Key` header and the request shapes stay byte-identical. Nothing about mobile signing depends on the app's bundle id, URL scheme, Keychain or the website at `chevron7.slovensko.app`, and nothing in this plan may make it depend on them: the QR code never points at our domain. Guarded by `RenameBoundaryTests` (Task 1), the boundary script, the existing `AppSettingsLearningTests.testMobileSigningDefaultsAndRoundTrip` (fresh settings after the rename default to the public relay with mobile signing on) and a real phone signature in Task 15.
- **Never renamed (the boundary):**
  1. `https://autogram.slovensko.digital/api/v1` (`AVMClient.publicBaseURL`), the QR host and `X-Encryption-Key`.
  2. `AVM*` type names and every UI string naming "Autogram v mobile".
  3. Everything under `engine/`, including `digital.slovensko.autogram.*`, the helper binaries `AutogramCLI-arm64` and `AutogramQuickActionRunner-arm64`, `autogram.jar`, the Swift type `AutogramCLIEngine` that drives that CLI, and the engine's own "Autogram macOS" strings (`PdfaNormalize` producer, Quick Action runner error). No `chevron7` string may enter `engine/`.
  4. `org.autogram.asice` (imported UTI).
  5. The machine protocol, including the `AUTOGRAM_KEY` record type the engine CLI prints.
  6. `ditec.isAutogram: true` in `WebExtension/dist/ditec.js`: portals branch on it; it comes from upstream `autogram-extension`.
  7. Record formats already stamped into legal records or files: FormPack id `autogram-p2e-legacy-swift-1.0` and the `PDFAValidator` match on `<pdf:Producer>Autogram PDFBox</pdf:Producer>`.
  8. Keychain service `digital.slovensko.autogram.timestamp-provider` in `UserPreferences.swift` (engine namespace).
- Development-only environment variables read by our code become `CHEVRON7_*` (`CHEVRON7_CLI_HELPER`, `CHEVRON7_JAVA_ENGINE_ROOT`, `CHEVRON7_ENGINE_LIVE_TEST`, `CHEVRON7_DIAG_PDF`, `CHEVRON7_LEGACY_APP_ROOT`). `AUTOGRAM_KEY` (engine output) and `AUTOGRAM_JAVA_HOME` (selects the JDK for building the Autogram engine fork, set in the user's shell) stay.
- No blind `sed s/autogram/chevron7/`. Every scripted replacement names exact tokens with word boundaries.
- Historical documents are records and keep their text: everything under `Autogram/docs/superpowers/`, dated findings (`*FINDINGS*.md`, `docs/SESSION_HANDOFF_*.md`), root `AUTOGRAM_*.md`, `*GROK*.md`, `index.html`, `design_assets/`, `docs/diagrams/`. Living docs are updated: `README.md`, `AGENTS.md`, `CLAUDE.md`, `Autogram/docs/EZZK-INTEGRATION.md`, `Autogram/docs/security-element-training.md`.
- No migration code. One-off shell actions in Phase B copy the data folders and back up the old UserDefaults domain.
- Slovak for user-facing strings, English for code, comments and docs. Never an em dash in any file. `AGENTS.md` and `CLAUDE.md` stay byte-identical.
- The package folder `Autogram/` becomes `Chevron7/` in Task 11, in its own commit, so every earlier task uses `Autogram/...` paths.
- Order differs from the spec on purpose: the spec tears down first, this plan does all repository work first because it never touches the system, and tears down immediately before the first install of Chevron7 (Task 12 before Task 14). What the spec guards against, two bundles and two Safari extensions live at once, still cannot happen, and the old app keeps working during Phase A.
- Work on branch `rename/chevron7` in the main checkout, not a worktree: the untracked engine build in `Autogram/.build/engine` is needed by `build_app.sh`.
- Build and test with `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"`. Baseline before Task 1: 430 + 97 tests, 0 failures.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## File Structure

| Path (before Task 11) | Responsibility | Tasks |
| --- | --- | --- |
| `Autogram/scripts/check-rename-boundary.sh` (new) | Fails if the boundary moves or, with `--strict`, if old names remain | 1, 11, 15 |
| `Autogram/Tests/AutogramKitTests/RenameBoundaryTests.swift` (new) | Pins the AVM relay URL | 1 |
| `Autogram/Sources/Chevron7Identity/ProductIdentity.swift` (new) | Every OS-visible name, one place | 3 |
| `Autogram/Tests/Chevron7KitTests/ProductIdentityTests.swift` (new) | Pins identity values and their consumers | 3, 4, 5 |
| `Autogram/Package.swift` | Target names and dependencies | 2, 3 |
| `Autogram/build_app.sh` | Bundle, appex, plists, entitlements, install | 2, 3, 4 |
| `Autogram/scripts/install-webbridge-agent.sh`, `Autogram/scripts/safari-spike.sh` | LaunchAgent and transport check | 2, 3 |
| `Autogram/WebExtension/dist/*` | Extension names, page API, channels | 3, 7 |
| `Autogram/Assets/Autogram Finder Quick Action.workflow` → `Chevron7 Finder Quick Action.workflow` | Finder signing | 6 |
| `LICENSE`, `NOTICE`, `Autogram/LICENSE` (new) | Split licensing | 9 |

---

## Task 0: Gate (user only)

Nothing below starts until the user confirms each line in chat. Record the answers in the commit message of Task 1.

- [x] Prefix: `app.slovensko.chevron7`, from `chevron7.slovensko.app` under the user's `slovensko.app` (confirmed 2026-09-22).
- [x] GitHub: rename `originalmagneto/autogram-macOS` to `originalmagneto/chevron7`, no placeholder repository under the old name (confirmed 2026-09-22).
- [x] Package folder `Autogram/` becomes `Chevron7/` (confirmed 2026-09-22).
- [x] Execution: subagent-driven (confirmed 2026-09-22).
- [x] The user accepts that Keychain items (EZZK password, AI provider API keys) and app settings do not carry over and are re-entered by hand (confirmed 2026-09-22).

If the bundle id changes, replace `app.slovensko.chevron7` in Global Constraints and in every task before starting; nothing else changes.

---

# Phase A: repository

### Task 1: Boundary guard

**Files:**
- Create: `Autogram/scripts/check-rename-boundary.sh`
- Create: `Autogram/Tests/AutogramKitTests/RenameBoundaryTests.swift`

**Interfaces:**
- Produces: `scripts/check-rename-boundary.sh [--strict]`, exit 0 when the boundary holds. Later tasks run it without arguments; Task 11 and Task 15 run it with `--strict`.

- [ ] **Step 1: Create the branch**

```bash
cd /Users/magneto/Projects/Autogram-macOS
git switch -c rename/chevron7
```

- [ ] **Step 2: Write the Swift boundary test**

`Autogram/Tests/AutogramKitTests/RenameBoundaryTests.swift`:

```swift
import XCTest
@testable import AutogramKit

/// The rename to Chevron7 stops where Autogram becomes a dependency. These pin
/// the values a later refactor could otherwise change without noticing.
final class RenameBoundaryTests: XCTestCase {
    /// The Autogram v mobile app opens links only for this host, so any other
    /// value silently breaks NFC signing with the phone.
    func testMobileRelayStaysOnSlovenskoDigital() {
        XCTAssertEqual(AVMClient.publicBaseURL.absoluteString, "https://autogram.slovensko.digital/api/v1")
    }

    /// The phone scans this link; a default client must produce it on the public host.
    func testQRCodeLinkPointsAtTheRelayThePhoneOpens() throws {
        let key = try AVMDocumentKey(bytes: Data(repeating: 7, count: 32))
        let reference = AVMDocumentReference(guid: "g1", key: key, lastModified: "")
        let url = AVMClient().qrCodeURL(for: reference)
        XCTAssertEqual(url.host, "autogram.slovensko.digital")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://autogram.slovensko.digital/api/v1/qr-code?guid=g1&key="))
    }
}
```

- [ ] **Step 3: Run it**

Run: `cd Autogram && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test --filter RenameBoundaryTests`
Expected: PASS, 2 tests (they pin today's values; they must still pass after every task).

- [ ] **Step 4: Write the boundary script**

`Autogram/scripts/check-rename-boundary.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Guards the line the Chevron7 rename stops at: Autogram is a dependency and an
# ancestor, not our name. Run it without arguments after every change. With
# --strict it also fails on old product names left in product code and living
# docs, which holds only once the rename is complete. Historical specs, plans
# and findings keep their text and are not scanned.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd -- "${script_dir}/.." && pwd)"
repo_root="$(cd -- "${package_root}/.." && pwd)"

strict=false
[[ "${1:-}" == "--strict" ]] && strict=true

failures=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✘\033[0m %s\n' "$1"; failures=$((failures + 1)); }

source_file() {
    find "${package_root}/Sources" "${package_root}/WebExtension" -name "$1" -not -path '*/.build/*' -print -quit
}

must_keep() {
    local file="$1" literal="$2"
    if [[ -n "$file" && -f "$file" ]] && grep -qF -- "$literal" "$file"; then
        ok "${file#"${repo_root}/"} keeps ${literal}"
    else
        fail "${file#"${repo_root}/"} lost ${literal}"
    fi
}

echo "▸ Nothing of ours inside the upstream engine"
if leaks="$(grep -rIil 'chevron7' "${repo_root}/engine" --exclude-dir=target 2>/dev/null)"; then
    fail "chevron7 in engine/: ${leaks//$'\n'/, }"
else
    ok "engine/ carries no chevron7"
fi

echo "▸ Autogram names we depend on"
avm_client="$(source_file AVMClient.swift)"
must_keep "$avm_client" 'URL(string: "https://autogram.slovensko.digital/api/v1")'
must_keep "$avm_client" '/qr-code?guid='
must_keep "$avm_client" 'forHTTPHeaderField: "X-Encryption-Key"'
if [[ -n "$avm_client" ]] && grep -rIil 'chevron7' "$(dirname "$avm_client")" >/dev/null 2>&1; then
    fail "chevron7 in the AVM sources"
else
    ok "AVM sources carry no chevron7"
fi
must_keep "${package_root}/build_app.sh" '<string>org.autogram.asice</string>'
must_keep "$(source_file SigningFlowViews.swift)" 'UTType(importedAs: "org.autogram.asice"'
must_keep "$(source_file ditec.js)" 'isAutogram: true'
must_keep "$(source_file FormPack.swift)" 'autogram-p2e-legacy-swift-1.0'
must_keep "$(source_file UserPreferences.swift)" 'digital.slovensko.autogram.timestamp-provider'

if $strict; then
    echo "▸ No old product names left (strict)"
    scanned=(
        "${package_root}/Sources" "${package_root}/Tests" "${package_root}/scripts"
        "${package_root}/build_app.sh" "${package_root}/WebExtension" "${package_root}/Assets"
        "${package_root}/docs/EZZK-INTEGRATION.md" "${package_root}/docs/security-element-training.md"
        "${repo_root}/README.md" "${repo_root}/AGENTS.md" "${repo_root}/CLAUDE.md" "${repo_root}/.gitignore"
    )
    # A missing path would make grep exit 2, which pipefail would report instead
    # of the hits, so scan only what exists.
    existing=()
    for path in "${scanned[@]}"; do [[ -e "$path" ]] && existing+=("$path"); done
    pattern='sk\.autogram|autogram://|Autogram macOS\.app|Autogram(Kit|App|WebBridge|WebExtension)|autogram-webbridge-agent|autogram-macos-|autogramMacOS|AUTOGRAM_(CLI_HELPER|JAVA_ENGINE_ROOT|ENGINE_LIVE_TEST|DIAG_PDF|LEGACY_APP_ROOT)|Application Support/Autogram'
    if hits="$(grep -rIEn --exclude-dir=.build -- "$pattern" "${existing[@]}" | grep -v 'scripts/check-rename-boundary.sh')"; then
        fail "old names remain:"
        printf '%s\n' "$hits" | sed 's/^/      /'
    else
        ok "no old product names in product code or living docs"
    fi
fi

if (( failures > 0 )); then
    echo "✘ ${failures} boundary check(s) failed"
    exit 1
fi
echo "✔ Boundary holds"
```

- [ ] **Step 5: Run it, then prove it bites**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
chmod +x scripts/check-rename-boundary.sh
scripts/check-rename-boundary.sh
```
Expected: all ✔, `✔ Boundary holds`, exit 0.

```bash
scripts/check-rename-boundary.sh --strict; echo "exit=$?"
```
Expected: `✘ old names remain:` with a long list, `exit=1`. This is correct before the rename.

```bash
echo "// chevron7" >> ../engine/README.md && scripts/check-rename-boundary.sh; echo "exit=$?"; git -C .. checkout -- engine/README.md
```
Expected: `✘ chevron7 in engine/`, `exit=1`, then the file is restored. If `engine/README.md` does not exist, use any tracked text file under `engine/`.

- [ ] **Step 6: Full suite**

Run: `cd Autogram && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test 2>&1 | tail -5`
Expected: 0 failures (baseline plus one test).

- [ ] **Step 7: Commit**

```bash
git add Autogram/scripts/check-rename-boundary.sh Autogram/Tests/AutogramKitTests/RenameBoundaryTests.swift
git commit -m "test: guard the Autogram boundary before the Chevron7 rename

Gate confirmed by the user: <paste the Task 0 answers>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Swift targets and the binaries they produce

**Files:**
- Move: `Autogram/Sources/{AutogramApp,AutogramKit,AutogramWebBridge,AutogramWebExtensionHandler,autogram-webbridge-agent}` → `Chevron7App`, `Chevron7Kit`, `Chevron7WebBridge`, `Chevron7WebExtensionHandler`, `chevron7-webbridge-agent`
- Move: `Autogram/Tests/{AutogramAppTests,AutogramKitTests}` → `Chevron7AppTests`, `Chevron7KitTests`
- Move: `Autogram/Sources/Chevron7App/AutogramApp.swift` → `Chevron7App.swift`
- Modify: `Autogram/Package.swift`, every `*.swift` under `Sources` and `Tests` that names a renamed token, `Autogram/build_app.sh` (lines 40, 234-245, 290), `Autogram/scripts/install-webbridge-agent.sh:9`, `Autogram/scripts/safari-spike.sh:39`

**Interfaces:**
- Produces: module names from Global Constraints; types `Chevron7App`, `Chevron7AppModel`, `Chevron7CommandActions`, `Chevron7CommandActionsKey`, `Chevron7Commands`, key path `\.chevron7CommandActions`, ObjC class `Chevron7WebExtensionHandler`; SwiftPM products `.build/.../Chevron7`, `chevron7-webbridge-agent`, `Chevron7WebExtensionHandler`.

- [ ] **Step 1: Move the directories**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
git mv Sources/AutogramApp Sources/Chevron7App
git mv Sources/AutogramKit Sources/Chevron7Kit
git mv Sources/AutogramWebBridge Sources/Chevron7WebBridge
git mv Sources/AutogramWebExtensionHandler Sources/Chevron7WebExtensionHandler
git mv Sources/autogram-webbridge-agent Sources/chevron7-webbridge-agent
git mv Tests/AutogramAppTests Tests/Chevron7AppTests
git mv Tests/AutogramKitTests Tests/Chevron7KitTests
git mv Sources/Chevron7App/AutogramApp.swift Sources/Chevron7App/Chevron7App.swift
```

- [ ] **Step 2: Replace exact tokens in Swift**

```bash
rg -l -g '*.swift' -e 'Autogram(Kit|App|WebBridge|WebExtensionHandler|AppModel|CommandActions|CommandActionsKey|Commands|KitTests|AppTests)\b' -e 'autogramCommandActions' Sources Tests \
  | xargs perl -pi -e '
      s/\bAutogramKitTests\b/Chevron7KitTests/g;
      s/\bAutogramAppTests\b/Chevron7AppTests/g;
      s/\bAutogramKit\b/Chevron7Kit/g;
      s/\bAutogramAppModel\b/Chevron7AppModel/g;
      s/\bAutogramApp\b/Chevron7App/g;
      s/\bAutogramWebBridge\b/Chevron7WebBridge/g;
      s/\bAutogramWebExtensionHandler\b/Chevron7WebExtensionHandler/g;
      s/\bAutogramCommandActionsKey\b/Chevron7CommandActionsKey/g;
      s/\bAutogramCommandActions\b/Chevron7CommandActions/g;
      s/\bAutogramCommands\b/Chevron7Commands/g;
      s/\bautogramCommandActions\b/chevron7CommandActions/g;'
```

Then confirm nothing else changed shape:

Run: `rg -n -g '*.swift' 'Autogram(Kit|App|WebBridge|WebExtensionHandler|Commands|CommandActions)\b|autogramCommandActions' Sources Tests`
Expected: no output. `AutogramCLIEngine` and `AutogramCLI` must still be present (`rg -c AutogramCLIEngine Sources Tests` non-zero).

- [ ] **Step 3: Rewrite `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chevron7",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Chevron7", targets: ["Chevron7App"]),
        .library(name: "Chevron7Kit", targets: ["Chevron7Kit"])
    ],
    targets: [
        .target(
            name: "Chevron7WebBridge",
            dependencies: []
        ),
        .target(
            name: "Chevron7Kit",
            dependencies: ["Chevron7WebBridge"]
        ),
        .executableTarget(
            name: "Chevron7App",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "pkcs11-helper",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "vision-eval",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "avm-probe",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "ezzk-probe",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "Chevron7WebExtensionHandler",
            dependencies: ["Chevron7WebBridge"]
        ),
        .executableTarget(
            name: "chevron7-webbridge-agent",
            dependencies: ["Chevron7WebBridge"]
        ),
        .executableTarget(
            name: "webbridge-probe",
            dependencies: ["Chevron7WebBridge"]
        ),
        .testTarget(
            name: "Chevron7KitTests",
            dependencies: ["Chevron7Kit"]
        ),
        .testTarget(
            name: "Chevron7AppTests",
            dependencies: ["Chevron7App"]
        )
    ]
)
```

The executable product `Chevron7` builds from target `Chevron7App`, so SwiftPM writes the binary as `Chevron7`.

- [ ] **Step 4: Point the scripts at the new binaries**

In `Autogram/build_app.sh` change only where binaries are read from, not what the bundle is called (Task 4 does that):

```bash
cp "$BIN_DIR/Chevron7" "$CONTENTS/MacOS/Autogram"
```
```bash
AGENT_BIN="$BIN_DIR/chevron7-webbridge-agent"
if [[ -x "$AGENT_BIN" ]]; then
    cp "$AGENT_BIN" "$CONTENTS/Helpers/chevron7-webbridge-agent" 2>/dev/null \
        || { mkdir -p "$CONTENTS/Helpers" && cp "$AGENT_BIN" "$CONTENTS/Helpers/chevron7-webbridge-agent"; }
fi

EXTENSION_BIN="$BIN_DIR/Chevron7WebExtensionHandler"
```
and in the appex `Info.plist` heredoc:
```xml
        <key>NSExtensionPrincipalClass</key>
        <string>Chevron7WebExtensionHandler</string>
```

In `Autogram/scripts/install-webbridge-agent.sh`:
```bash
AGENT="$APP/Contents/Helpers/chevron7-webbridge-agent"
```

In `Autogram/scripts/safari-spike.sh` step 3:
```bash
[[ "$CLASS" == "Chevron7WebExtensionHandler" ]] && ok "principal class: $CLASS" || bad "principal class: '$CLASS'"
```

- [ ] **Step 5: Build, test, assemble**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift build 2>&1 | tail -3
swift test 2>&1 | tail -5
./build_app.sh 2>&1 | tail -3
BIN="$(swift build --show-bin-path)"
ls "$BIN/Autogram.app/Contents/MacOS" "$BIN/Autogram.app/Contents/Helpers" | grep -E 'Autogram$|chevron7-webbridge-agent'
/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPrincipalClass" "$BIN/Autogram.app/Contents/PlugIns/AutogramWebExtension.appex/Contents/Info.plist"
scripts/check-rename-boundary.sh
```
Expected: build succeeds; tests 0 failures; `Autogram` and `chevron7-webbridge-agent` listed; principal class `Chevron7WebExtensionHandler`; boundary holds. The bundle is still named `Autogram.app` until Task 4.

- [ ] **Step 6: Commit**

```bash
git add -A Sources Tests Package.swift build_app.sh scripts
git commit -m "refactor: rename Swift targets and modules to Chevron7

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `Chevron7Identity` and the web bridge names

These names must match at install time or the XPC transport fails with no visible error, so they change together: Mach service, LaunchAgent label, appex bundle id, `NATIVE_APP`, the appex entitlement and both scripts.

**Files:**
- Create: `Autogram/Sources/Chevron7Identity/ProductIdentity.swift`
- Create: `Autogram/Tests/Chevron7KitTests/ProductIdentityTests.swift`
- Modify: `Autogram/Package.swift`, `Autogram/Sources/Chevron7WebBridge/WebSigningBridge.swift:67-70`, `Autogram/Sources/chevron7-webbridge-agent/main.swift:74-95`, `Autogram/build_app.sh` (appex block 240-316 and pluginkit line 339), `Autogram/WebExtension/dist/background.js:8`, `Autogram/scripts/install-webbridge-agent.sh`, `Autogram/scripts/safari-spike.sh`

**Interfaces:**
- Produces (`import Chevron7Identity`):
  - `ProductIdentity.name: String` = `"Chevron7"`
  - `ProductIdentity.bundleIdentifier: String` = `"app.slovensko.chevron7"`
  - `ProductIdentity.webExtensionBundleIdentifier: String` = `"app.slovensko.chevron7.WebExtension"`
  - `ProductIdentity.webBridgeServiceName: String` = `"app.slovensko.chevron7.webbridge"`
  - `ProductIdentity.urlScheme: String` = `"chevron7"`
  - `ProductIdentity.installedAppURL: URL` = `/Applications/Chevron7.app`
  - `ProductIdentity.applicationSupportDirectory(fileManager: FileManager = .default) -> URL` = `~/Library/Application Support/Chevron7`
  - `ProductIdentity.cachesDirectory(fileManager: FileManager = .default) -> URL` = `~/Library/Caches/Chevron7`

- [ ] **Step 1: Write the failing test**

`Autogram/Tests/Chevron7KitTests/ProductIdentityTests.swift`:

```swift
import XCTest
import Chevron7Identity
@testable import Chevron7WebBridge

/// Every name macOS knows the product by. The literals are repeated on purpose:
/// build_app.sh and the scripts carry the same strings, and a changed value here
/// must be changed there too.
final class ProductIdentityTests: XCTestCase {
    func testBundleNamesShareOnePrefix() {
        XCTAssertEqual(ProductIdentity.name, "Chevron7")
        XCTAssertEqual(ProductIdentity.bundleIdentifier, "app.slovensko.chevron7")
        XCTAssertEqual(ProductIdentity.webExtensionBundleIdentifier, "app.slovensko.chevron7.WebExtension")
        XCTAssertEqual(ProductIdentity.webBridgeServiceName, "app.slovensko.chevron7.webbridge")
        XCTAssertEqual(ProductIdentity.urlScheme, "chevron7")
        XCTAssertEqual(ProductIdentity.installedAppURL.path, "/Applications/Chevron7.app")
    }

    func testWebBridgeUsesTheIdentity() {
        XCTAssertEqual(WebSigningBridge.machServiceName, "app.slovensko.chevron7.webbridge")
        XCTAssertEqual(WebSigningBridge.agentLabel, "app.slovensko.chevron7.webbridge")
    }

    func testDataRootsAreNamedAfterTheProduct() {
        XCTAssertEqual(ProductIdentity.applicationSupportDirectory().lastPathComponent, "Chevron7")
        XCTAssertEqual(ProductIdentity.applicationSupportDirectory().deletingLastPathComponent().lastPathComponent, "Application Support")
        XCTAssertEqual(ProductIdentity.cachesDirectory().lastPathComponent, "Chevron7")
        XCTAssertEqual(ProductIdentity.cachesDirectory().deletingLastPathComponent().lastPathComponent, "Caches")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd Autogram && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test --filter ProductIdentityTests 2>&1 | tail -5`
Expected: FAIL to compile with `no such module 'Chevron7Identity'`.

- [ ] **Step 3: Create the module**

`Autogram/Sources/Chevron7Identity/ProductIdentity.swift`:

```swift
import Foundation

/// Every name macOS and Safari know this product by, in one place.
///
/// `build_app.sh`, `scripts/install-webbridge-agent.sh`, `scripts/safari-spike.sh`
/// and `WebExtension/dist/background.js` repeat these literals because they cannot
/// import Swift; `ProductIdentityTests` pins the values so a change here shows up
/// as a failing test until the scripts follow.
public enum ProductIdentity {
    public static let name = "Chevron7"
    public static let bundleIdentifier = "app.slovensko.chevron7"
    public static let webExtensionBundleIdentifier = "app.slovensko.chevron7.WebExtension"
    /// Mach service the launchd agent owns, and the agent's label.
    public static let webBridgeServiceName = "app.slovensko.chevron7.webbridge"
    public static let urlScheme = "chevron7"
    public static let installedAppURL = URL(fileURLWithPath: "/Applications/Chevron7.app", isDirectory: true)

    /// `~/Library/Application Support/Chevron7`, the one root for every file the app keeps.
    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    /// `~/Library/Caches/Chevron7`, for files the app can always recreate.
    public static func cachesDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }
}
```

In `Autogram/Package.swift` add the target first in `targets:` and wire the dependencies:

```swift
        .target(
            name: "Chevron7Identity",
            dependencies: []
        ),
        .target(
            name: "Chevron7WebBridge",
            dependencies: ["Chevron7Identity"]
        ),
        .target(
            name: "Chevron7Kit",
            dependencies: ["Chevron7WebBridge", "Chevron7Identity"]
        ),
        .executableTarget(
            name: "Chevron7App",
            dependencies: ["Chevron7Kit", "Chevron7Identity"]
        ),
```
```swift
        .executableTarget(
            name: "chevron7-webbridge-agent",
            dependencies: ["Chevron7WebBridge", "Chevron7Identity"]
        ),
```
```swift
        .testTarget(
            name: "Chevron7KitTests",
            dependencies: ["Chevron7Kit", "Chevron7Identity", "Chevron7WebBridge"]
        ),
```

- [ ] **Step 4: Point the web bridge at it**

`Autogram/Sources/Chevron7WebBridge/WebSigningBridge.swift`: add `import Chevron7Identity` below the existing imports, then:

```swift
    public static let machServiceName = ProductIdentity.webBridgeServiceName

    /// Label of the launchd agent that owns ``machServiceName``.
    public static let agentLabel = ProductIdentity.webBridgeServiceName
```

`Autogram/Sources/chevron7-webbridge-agent/main.swift`: add `import Chevron7Identity`, then:

```swift
            FileHandle.standardError.write(Data("Chevron7 bundle not found\n".utf8))
```
```swift
            .deletingLastPathComponent()   // Chevron7.app
```
```swift
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProductIdentity.bundleIdentifier)
```
```swift
        !NSRunningApplication.runningApplications(withBundleIdentifier: ProductIdentity.bundleIdentifier).isEmpty
```

- [ ] **Step 5: Run the test to see it pass**

Run: `cd Autogram && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test --filter ProductIdentityTests 2>&1 | tail -3`
Expected: PASS, 3 tests.

- [ ] **Step 6: Match the literals outside Swift**

`Autogram/build_app.sh`, appex block:

```bash
EXTENSION_BIN="$BIN_DIR/Chevron7WebExtensionHandler"
if [[ -x "$EXTENSION_BIN" ]]; then
    APPEX="$CONTENTS/PlugIns/Chevron7WebExtension.appex"
    rm -rf "$APPEX"
    mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
    cp "$EXTENSION_BIN" "$APPEX/Contents/MacOS/Chevron7WebExtension"
```
```xml
    <key>CFBundleName</key>
    <string>Chevron7</string>
    <key>CFBundleDisplayName</key>
    <string>Chevron7</string>
    <key>CFBundleIdentifier</key>
    <string>app.slovensko.chevron7.WebExtension</string>
    <key>CFBundleExecutable</key>
    <string>Chevron7WebExtension</string>
```
```bash
    APPEX_ENTITLEMENTS="$(mktemp -t chevron7-appex-entitlements).plist"
```
```xml
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>app.slovensko.chevron7.webbridge</string>
    </array>
```
and in the install block (the app path itself changes in Task 4):
```bash
    INSTALLED_APPEX="$INSTALL_DIR/Contents/PlugIns/Chevron7WebExtension.appex"
```
```bash
            if pluginkit -m -i app.slovensko.chevron7.WebExtension 2>/dev/null | grep -q WebExtension; then
```

`Autogram/WebExtension/dist/background.js:8`:
```js
const NATIVE_APP = "app.slovensko.chevron7.WebExtension";
```

`Autogram/scripts/install-webbridge-agent.sh`:
```bash
APP="${1:-/Applications/Chevron7.app}"
LABEL="app.slovensko.chevron7.webbridge"
AGENT="$APP/Contents/Helpers/chevron7-webbridge-agent"
```

`Autogram/scripts/safari-spike.sh`:
```bash
APP="/Applications/Chevron7.app"
APPEX="$APP/Contents/PlugIns/Chevron7WebExtension.appex"
SERVICE="app.slovensko.chevron7.webbridge"
```
```bash
if launchctl print "gui/$(id -u)/$SERVICE" >/dev/null 2>&1; then
    ok "agent $SERVICE je v launchd"
```
```bash
if ! pgrep -x "Chevron7" >/dev/null 2>&1; then
```
```bash
    bad "XPC spojenie zlyhalo - pozri log: log show --last 2m --predicate 'subsystem == \"app.slovensko.chevron7\"'"
```
In the manual text: `3. Safari > Settings > Extensions > zapni "Chevron7"`, `await window.chevron7.status()` and `{ ok:false, error:"Chevron7 nebeží..." }`.

- [ ] **Step 7: Verify the names line up in the assembled bundle**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift test 2>&1 | tail -3
./build_app.sh 2>&1 | tail -2
APPEX="$(swift build --show-bin-path)/Autogram.app/Contents/PlugIns/Chevron7WebExtension.appex"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APPEX/Contents/Info.plist"
codesign -d --entitlements - "$APPEX" 2>/dev/null | grep -o 'app.slovensko.chevron7.webbridge'
grep -o '"app.slovensko.chevron7.WebExtension"' "$APPEX/Contents/Resources/background.js"
rg -n 'sk\.autogram\.Autogram\.(webbridge|WebExtension)' Sources scripts build_app.sh WebExtension
scripts/check-rename-boundary.sh
```
Expected: 0 test failures; `app.slovensko.chevron7.WebExtension`; the service name once; the `NATIVE_APP` literal once; the `rg` prints nothing; boundary holds.

- [ ] **Step 8: Commit**

```bash
git add -A Sources Tests Package.swift build_app.sh scripts WebExtension/dist/background.js
git commit -m "feat: name the web bridge app.slovensko.chevron7 from one identity module

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The application bundle, URL scheme, install path and environment variables

**Files:**
- Move: `Autogram/Assets/Autogram.icns` → `Autogram/Assets/Chevron7.icns`
- Modify: `Autogram/build_app.sh` (header, lines 34-51, 108-164, 324-339), `Autogram/Sources/Chevron7Kit/EZZK/EZZKOAuthModels.swift:10-11`, `Autogram/Tests/Chevron7KitTests/EZZKEnvironmentTests.swift:51-111`, `Autogram/Sources/Chevron7Kit/Signing/JavaEngine/JavaEngineLocator.swift:25-28`, `Autogram/Sources/Chevron7Kit/Signing/PKCS11BridgeClient.swift:64`, `Autogram/Sources/Chevron7Kit/EngineBridge/CLI/AutogramCLIEngine.swift:709`, `Autogram/Tests/Chevron7AppTests/AppLaunchModeTests.swift`, `Autogram/Sources/Chevron7App/AppLaunchMode.swift:3-4`, `Autogram/Tests/Chevron7KitTests/EngineBridgeTests.swift:440-505`, `Autogram/Tests/Chevron7KitTests/LiveEngineInspectionTests.swift:7-8`, `Autogram/Tests/Chevron7KitTests/RealScanSmokeTests.swift:5-10`, `Autogram/build_app.sh:49`, `Autogram/Tests/Chevron7KitTests/ProductIdentityTests.swift`

**Interfaces:**
- Consumes: `ProductIdentity.urlScheme`, `ProductIdentity.installedAppURL` (Task 3).
- Produces: `EZZKOAuthConfiguration.nativeRedirectURI` = `chevron7://ezzk/callback`, `nativeCallbackScheme` = `"chevron7"`; `JavaEngineLocator.environmentKey` = `"CHEVRON7_JAVA_ENGINE_ROOT"`, `defaultRoots` = `["/Applications/Chevron7.app/Contents"]`.

- [ ] **Step 1: Write the failing tests**

Append to `ProductIdentityTests` (add `@testable import Chevron7Kit` at the top):

```swift
    func testURLSchemeAndInstallPathFollowTheIdentity() {
        XCTAssertEqual(EZZKOAuthConfiguration.nativeCallbackScheme, "chevron7")
        XCTAssertEqual(EZZKOAuthConfiguration.nativeRedirectURI.absoluteString, "chevron7://ezzk/callback")
        XCTAssertEqual(JavaEngineLocator.defaultRoots, ["/Applications/Chevron7.app/Contents"])
        XCTAssertEqual(JavaEngineLocator.environmentKey, "CHEVRON7_JAVA_ENGINE_ROOT")
    }
```

In `EZZKEnvironmentTests.swift` replace every `"autogram://ezzk/callback` with `"chevron7://ezzk/callback` (4 places, one with a query string) and `callbackScheme: "autogram"` with `callbackScheme: "chevron7"` (2 places).

`AppLaunchModeTests.swift`:
```swift
    func testWebSigningArgumentSelectsBackgroundMode() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Chevron7.app/Contents/MacOS/Chevron7", "--web-signing"]), .webSigning)
    }

    func testOrdinaryLaunchIsNormal() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Chevron7.app/Contents/MacOS/Chevron7"]), .normal)
        XCTAssertEqual(AppLaunchMode.from(arguments: ["Chevron7", "-NSDocumentRevisionsDebugMode", "YES"]), .normal)
    }
```

- [ ] **Step 2: Run to see the failures**

Run: `cd Autogram && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test --filter 'ProductIdentityTests|EZZKEnvironmentTests' 2>&1 | grep -E 'error|failed' | head`
Expected: FAIL on the scheme, redirect URI, default roots and environment key.

- [ ] **Step 3: Implement**

`EZZKOAuthModels.swift` (add `import Chevron7Identity`):
```swift
    public static let nativeRedirectURI = URL(string: "\(ProductIdentity.urlScheme)://ezzk/callback")!
    public static let nativeCallbackScheme = ProductIdentity.urlScheme
```
The Keycloak client is not wired yet; whoever registers it with EZZK must register `chevron7://ezzk/callback`.

`JavaEngineLocator.swift` (add `import Chevron7Identity`):
```swift
    public static let environmentKey = "CHEVRON7_JAVA_ENGINE_ROOT"
    public static let defaultRoots = [
        ProductIdentity.installedAppURL.appendingPathComponent("Contents").path
    ]
```

`PKCS11BridgeClient.swift:64` (add `import Chevron7Identity`):
```swift
            ProductIdentity.installedAppURL.appendingPathComponent("Contents/MacOS/pkcs11-helper")
```

`AutogramCLIEngine.swift:709`: `environment["CHEVRON7_CLI_HELPER"]`.
`AppLaunchMode.swift:4`: `/// portal request finds Chevron7 not running; that launch shows only the signing panel.`

Environment variables, exact replacements:
```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
rg -l -e 'AUTOGRAM_(ENGINE_LIVE_TEST|DIAG_PDF|LEGACY_APP_ROOT)\b' Tests Sources scripts build_app.sh \
  | xargs perl -pi -e 's/\bAUTOGRAM_(ENGINE_LIVE_TEST|DIAG_PDF|LEGACY_APP_ROOT)\b/CHEVRON7_$1/g'
rg -n 'AUTOGRAM_' Sources Tests scripts build_app.sh
```
Expected output of the last command: only `AUTOGRAM_JAVA_HOME` in `scripts/build-engine.sh`, which stays.

- [ ] **Step 4: Rename the bundle in `build_app.sh`**

```bash
git mv Assets/Autogram.icns Assets/Chevron7.icns
```

`build_app.sh`:
```bash
# Chevron7.app build script - assembly of a macOS app bundle.
```
```bash
APP_DIR="$BIN_DIR/Chevron7.app"
```
```bash
cp "$BIN_DIR/Chevron7" "$CONTENTS/MacOS/Chevron7"
```
```bash
cp "Assets/Chevron7.icns" "$CONTENTS/Resources/Chevron7.icns"
```
Main `Info.plist` heredoc:
```xml
    <key>CFBundleIconFile</key>
    <string>Chevron7</string>
    <key>CFBundleName</key>
    <string>Chevron7</string>
    <key>CFBundleDisplayName</key>
    <string>Chevron7</string>
    <key>CFBundleIdentifier</key>
    <string>app.slovensko.chevron7</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>app.slovensko.chevron7.ezzk</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>chevron7</string>
            </array>
        </dict>
    </array>
```
```xml
    <key>CFBundleExecutable</key>
    <string>Chevron7</string>
```
```xml
                <string>Chevron7 Signing Bridge</string>
            </dict>
            <key>NSMessage</key>
            <string>signFiles</string>
            <key>NSPortName</key>
            <string>Chevron7</string>
```
Leave both `org.autogram.asice` entries untouched. Install block:
```bash
    INSTALL_DIR="/Applications/Chevron7.app"
```

- [ ] **Step 5: Test and assemble**

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift test 2>&1 | tail -3
./build_app.sh 2>&1 | tail -2
APP="$(swift build --show-bin-path)/Chevron7.app"
for key in CFBundleIdentifier CFBundleExecutable CFBundleName CFBundleIconFile 'CFBundleURLTypes:0:CFBundleURLSchemes:0' 'UTImportedTypeDeclarations:0:UTTypeIdentifier'; do
  printf '%s = ' "$key"; /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist"
done
ls "$APP/Contents/MacOS/Chevron7" "$APP/Contents/Resources/Chevron7.icns"
scripts/check-rename-boundary.sh
```
Expected: 0 failures; `app.slovensko.chevron7`, `Chevron7`, `Chevron7`, `Chevron7`, `chevron7`, `org.autogram.asice`; both files exist; boundary holds.

- [ ] **Step 6: Commit**

```bash
git add -A Assets Sources Tests build_app.sh scripts
git commit -m "feat: build and install the app as Chevron7.app with the chevron7 scheme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Persisted state: Keychain, UserDefaults, log subsystems and one data root

**Files:**
- Modify: `Autogram/Sources/Chevron7Kit/Support/AppSettings.swift:5,313`, `Autogram/Sources/Chevron7Kit/EZZK/EZZKTokenStore.swift:33`, `Autogram/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPCredentialStore.swift:25`, `Autogram/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPResponse.swift:54`, `Autogram/Sources/Chevron7Kit/EngineBridge/Signing/SignaturePlacementState.swift:192`, `Autogram/Sources/Chevron7Kit/Evidence/LocalEvidenceStore.swift:121-127`, `Autogram/Sources/Chevron7Kit/Signing/JavaEngine/EngineBridgeSigningProvider.swift:29,750`, `Autogram/Sources/Chevron7Kit/VisionAI/Learning/ExampleBank.swift:67-70`, `Autogram/Sources/Chevron7Kit/EngineBridge/Assets/SignatureAssetStore.swift:31-35`, `Autogram/Sources/Chevron7Kit/EngineBridge/Assets/VisibleSignatureRenderer.swift:25,57`, `Autogram/Sources/Chevron7Kit/EngineBridge/CLI/AutogramCLIEngine.swift:155`, `Autogram/Sources/Chevron7App/RecentDocumentStore.swift:14`, `Autogram/Sources/Chevron7App/SignedDocumentStore.swift:72`, `Autogram/Sources/Chevron7App/WebBridgeListener.swift:14`, `Autogram/Sources/Chevron7App/WebSigningCoordinator.swift:80`, `Autogram/Sources/Chevron7App/WebSigningPrompt.swift:35`, `Autogram/Sources/Chevron7App/VisualSignatureStore.swift:16`, `Autogram/Sources/Chevron7App/SigningSessionStore.swift:1583`, `Autogram/Sources/Chevron7App/ZakoSessionStore.swift:1475,1480`, `Autogram/Sources/Chevron7App/Views/WebSigningDocumentPreview.swift:64`
- Test: `Autogram/Tests/Chevron7AppTests/RecentDocumentStoreTests.swift` (5 literals), `Autogram/Tests/Chevron7KitTests/EZZKSOAPCredentialStoreTests.swift:18`, `Autogram/Tests/Chevron7KitTests/ProductIdentityTests.swift`

**Interfaces:**
- Consumes: `ProductIdentity.bundleIdentifier`, `applicationSupportDirectory()`, `cachesDirectory()`.
- Produces: Keychain services `app.slovensko.chevron7` (API keys), `app.slovensko.chevron7.ezzk.soap`, `app.slovensko.chevron7.ezzk.oauth.tokens`; UserDefaults keys `app.slovensko.chevron7.settings.v1`, `app.slovensko.chevron7.recentDocuments.v1`, `app.slovensko.chevron7.signedDocuments.v1`, `app.slovensko.chevron7.visibleSignature`; log subsystem `app.slovensko.chevron7` for every logger; data under `ProductIdentity.applicationSupportDirectory()` in `Evidence`, `Output`, `Templates`, `VisionBank`, `Signatures`, `Visual Signatures`.

- [ ] **Step 1: Write the failing tests**

`EZZKSOAPCredentialStoreTests.swift:18`:
```swift
        XCTAssertEqual(keychain.services, ["app.slovensko.chevron7.ezzk.soap"])
```

`RecentDocumentStoreTests.swift`: replace all 5 occurrences of `"sk.autogram.recentDocuments.v1"` with `"app.slovensko.chevron7.recentDocuments.v1"`.

Append to `ProductIdentityTests`:
```swift
    func testStoredStateLivesUnderTheIdentity() {
        let root = ProductIdentity.applicationSupportDirectory()
        XCTAssertEqual(ExampleBank.defaultDirectory, root.appendingPathComponent("VisionBank", isDirectory: true))
        XCTAssertEqual(EZZKSOAPCredentialStore.keychainService, "app.slovensko.chevron7.ezzk.soap")
        XCTAssertEqual(EZZKTokenStore.keychainService, "app.slovensko.chevron7.ezzk.oauth.tokens")
        XCTAssertEqual(KeychainStore.service, "app.slovensko.chevron7")
        XCTAssertEqual(AppSettings.storageKey, "app.slovensko.chevron7.settings.v1")
        XCTAssertEqual(SignaturePlacementState.preferencesKey, "app.slovensko.chevron7.visibleSignature")
    }

    func testSignatureArtworkSharesTheDataRoot() {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SignatureAssetStore(applicationSupportRoot: work)
        XCTAssertEqual(store.assetsDirectory.standardizedFileURL.path,
                       work.appendingPathComponent("Chevron7/Visual Signatures").standardizedFileURL.path)
    }
```
All six symbols are `internal static let` members (checked 2026-09-22), which `@testable import Chevron7Kit` reaches.

- [ ] **Step 2: Run to see the failures**

Run: `cd Autogram && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test --filter 'ProductIdentityTests|EZZKSOAPCredentialStoreTests|RecentDocumentStoreTests' 2>&1 | grep -cE 'error:|failed'`
Expected: a non-zero count.

- [ ] **Step 3: Implement**

Add `import Chevron7Identity` to each modified Swift file that lacks it, then:

`AppSettings.swift`:
```swift
    static let service = ProductIdentity.bundleIdentifier
```
```swift
    static let storageKey = "\(ProductIdentity.bundleIdentifier).settings.v1"
```
`EZZKTokenStore.swift:33`:
```swift
    static let keychainService = "\(ProductIdentity.bundleIdentifier).ezzk.oauth.tokens"
```
`EZZKSOAPCredentialStore.swift:25`:
```swift
    static let keychainService = "\(ProductIdentity.bundleIdentifier).ezzk.soap"
```
`SignaturePlacementState.swift:192`:
```swift
    static let preferencesKey = "\(ProductIdentity.bundleIdentifier).visibleSignature"
```
`RecentDocumentStore.swift:14` and `SignedDocumentStore.swift:72`:
```swift
    private static let storageKey = "\(ProductIdentity.bundleIdentifier).recentDocuments.v1"
```
```swift
    private static let storageKey = "\(ProductIdentity.bundleIdentifier).signedDocuments.v1"
```
Loggers (`EZZKSOAPResponse.swift:54`, `EngineBridgeSigningProvider.swift:29`, `WebBridgeListener.swift:14`, `WebSigningCoordinator.swift:80`, `WebSigningPrompt.swift:35`): replace the `subsystem:` argument with `ProductIdentity.bundleIdentifier`, keeping each `category:`. Example:
```swift
    private let log = Logger(subsystem: ProductIdentity.bundleIdentifier, category: "web-bridge")
```
`LocalEvidenceStore.swift`:
```swift
    private let queue = DispatchQueue(label: "\(ProductIdentity.bundleIdentifier).evidence")
```
```swift
        let base = directory ?? ProductIdentity.applicationSupportDirectory()
            .appendingPathComponent("Evidence", isDirectory: true)
```
`ExampleBank.swift`:
```swift
    public static var defaultDirectory: URL {
        ProductIdentity.applicationSupportDirectory().appendingPathComponent("VisionBank", isDirectory: true)
    }
```
`SignatureAssetStore.swift` (the root stays injectable for tests):
```swift
    public var assetsDirectory: URL {
        applicationSupportRoot
            .appending(path: ProductIdentity.name, directoryHint: .isDirectory)
            .appending(path: "Visual Signatures", directoryHint: .isDirectory)
    }
```
`VisibleSignatureRenderer.swift:57`:
```swift
        let directory = cacheRoot.appending(path: "\(ProductIdentity.name)/Visual Signatures", directoryHint: .isDirectory)
```
`SigningSessionStore.swift` and `ZakoSessionStore.swift`:
```swift
    static func outputDirectoryURL() -> URL {
        ProductIdentity.applicationSupportDirectory().appendingPathComponent("Output", isDirectory: true)
    }
```
```swift
    static func templatesDirectory() -> URL {
        let url = ProductIdentity.applicationSupportDirectory().appendingPathComponent("Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
```
`VisualSignatureStore.swift`:
```swift
        let url = ProductIdentity.applicationSupportDirectory().appendingPathComponent("Signatures", isDirectory: true)
```
Temporary folders: `WebSigningDocumentPreview.swift:64` `"Chevron7WebPreview"`, `AutogramCLIEngine.swift:155` `"Chevron7-EmbeddedPreviews"`, `EngineBridgeSigningProvider.swift:750` `"chevron7-engine"`.

Do not touch `UserPreferences.swift:107` (`digital.slovensko.autogram.timestamp-provider`).

- [ ] **Step 4: Verify**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift test 2>&1 | tail -3
rg -n 'sk\.autogram|"Autogram/|Autogram macOS' Sources
scripts/check-rename-boundary.sh
```
Expected: 0 failures; `rg` prints only lines that Task 8 owns (user-facing strings) and nothing matching `sk.autogram` or `"Autogram/`; boundary holds.

- [ ] **Step 5: Commit**

```bash
git add -A Sources Tests
git commit -m "feat: keep settings, secrets and data under the Chevron7 identity

One data root now: Application Support/Chevron7 also holds the visual
signatures that lived in Application Support/Autogram macOS.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Finder Quick Action

**Files:**
- Move: `Autogram/Assets/Autogram Finder Quick Action.workflow` → `Autogram/Assets/Chevron7 Finder Quick Action.workflow`
- Move inside it: `Contents/Resources/autogram-cli-sign.sh` → `chevron7-cli-sign.sh`, `autogram-quick-action.sh` → `chevron7-quick-action.sh`
- Modify: the workflow's `Contents/Info.plist:15`, `Contents/document.wflow` (lines 38-39, 66-67), both scripts, `Autogram/Sources/Chevron7App/ServicesProvider.swift:4-6`, `Autogram/build_app.sh:45`

**Interfaces:**
- Produces: `ServicesProvider.menuTitle` = `"Podpísať s QES + QTS (Chevron7)"`, `workflowResourceName` = `"Chevron7 Finder Quick Action"`, `workflowInstallName` = `"Chevron7 Finder Quick Action.workflow"`.

- [ ] **Step 1: Move**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
git mv "Assets/Autogram Finder Quick Action.workflow" "Assets/Chevron7 Finder Quick Action.workflow"
W="Assets/Chevron7 Finder Quick Action.workflow/Contents"
git mv "$W/Resources/autogram-cli-sign.sh" "$W/Resources/chevron7-cli-sign.sh"
git mv "$W/Resources/autogram-quick-action.sh" "$W/Resources/chevron7-quick-action.sh"
```

- [ ] **Step 2: Edit**

`$W/Info.plist:15`: `<string>Podpísať s QES + QTS (Chevron7)</string>`

`$W/document.wflow`, both shell blocks:
```
workflow_resources="$HOME/Library/Services/Chevron7 Finder Quick Action.workflow/Contents/Resources"
exec "${workflow_resources}/chevron7-quick-action.sh" "$@"
```

`chevron7-cli-sign.sh`:
```bash
    "/Applications/Chevron7.app/Contents/Helpers/AutogramCLI-arm64"
    "$HOME/Applications/Chevron7.app/Contents/Helpers/AutogramCLI-arm64"
```
```bash
  done < <(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "app.slovensko.chevron7"' 2>/dev/null || true)
```
Usage text: `chevron7-cli-sign.sh [options] <PDF>` and `Chevron7 and an arm64-capable PKCS#11 driver are required.`; line 78: `Chevron7 ARM64 helper was not found.` Keep `AutogramCLI-arm64` and `AutogramQuickActionRunner-arm64` (engine binaries).

`chevron7-quick-action.sh`:
```bash
CLI_SCRIPT="$SCRIPT_DIR/chevron7-cli-sign.sh"
```
Dialog titles `"Chevron7: CLI podpis PDF"`, `"Chevron7: podpisový certifikát"`, `"Chevron7: podpisový PIN"`; every `show_alert "Autogram"` becomes `show_alert "Chevron7"`; `mktemp -d -t chevron7-quick-action`. Keep both `AUTOGRAM_KEY` lines (engine output record type).

`ServicesProvider.swift`:
```swift
    static let menuTitle = "Podpísať s QES + QTS (Chevron7)"
    static let workflowResourceName = "Chevron7 Finder Quick Action"
    static let workflowInstallName = "Chevron7 Finder Quick Action.workflow"
```

`build_app.sh:45`:
```bash
ditto "Assets/Chevron7 Finder Quick Action.workflow" "$CONTENTS/Resources/Chevron7 Finder Quick Action.workflow"
```

- [ ] **Step 3: Verify**

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
bash -n "$W/Resources/chevron7-cli-sign.sh" && bash -n "$W/Resources/chevron7-quick-action.sh" && echo syntax-ok
plutil -lint "$W/Info.plist" "$W/document.wflow"
rg -n -i 'autogram' "Assets/Chevron7 Finder Quick Action.workflow" | rg -v 'AutogramCLI-arm64|AutogramQuickActionRunner-arm64|AUTOGRAM_KEY'
swift build 2>&1 | tail -1 && ./build_app.sh 2>&1 | tail -1
ls "$(swift build --show-bin-path)/Chevron7.app/Contents/Resources/" | grep 'Chevron7 Finder Quick Action.workflow'
scripts/check-rename-boundary.sh
```
Expected: `syntax-ok`; both plists OK; the `rg` prints nothing; the workflow is in the bundle; boundary holds.

- [ ] **Step 4: Commit**

```bash
git add -A Assets Sources build_app.sh
git commit -m "feat: ship the Finder Quick Action as Chevron7

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Web extension names, page API and channels

**Files:**
- Modify: `Autogram/WebExtension/dist/manifest.json:3,14,64`, `_locales/sk/messages.json:3,6`, `popup.html:2,18,21`, `popup.js:19`, `background.js:10,29`, `content.js`, `ditec.js`, `inject.js`, `Autogram/Tests/Chevron7KitTests/WebSignRequestWireFormatTests.swift` (comments only, if they name the channels)

**Interfaces:**
- Produces: page API `window.chevron7` with `isChevron7: true`, `status()`, `sign(request)`; `ditec.isChevron7: true`; DOM event names `chevron7-request`, `chevron7-response`, `chevron7-set-enabled`; request ids `chevron7-<time>-<n>`. `ditec.isAutogram: true` is unchanged.

- [ ] **Step 1: Replace the internal tokens**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram/WebExtension/dist
perl -pi -e '
  s/"autogram-macos-(request|response|set-enabled)"/"chevron7-$1"/g;
  s/\bautogramMacOS\b/chevron7/g;
  s/__autogramMacOSContentScript/__chevron7ContentScript/g;
  s/\bisAutogramMacOS\b/isChevron7/g;
  s/\[Autogram macOS\]/[Chevron7]/g;
  s/"autogram-" \+ Date\.now\(\)/"chevron7-" + Date.now()/g;
  s/`autogram-\$\{Date\.now\(\)\}/`chevron7-\${Date.now()}/g;' content.js ditec.js inject.js
```

In `inject.js` rename the local object and its flag by hand (it is ours; the portal flag lives on `ditec`, not here):
```js
  const chevron7 = {
    isChevron7: true,

    /** Whether Chevron7 is running and ready to sign. */
```
```js
  Object.defineProperty(window, "chevron7", {
    value: Object.freeze(chevron7),
```

- [ ] **Step 2: Replace the user-facing strings**

| File | New text |
| --- | --- |
| `manifest.json` `name`, `action.default_title` | `Chevron7` |
| `manifest.json` `description` | `Podpisovanie na štátnych weboch cez Chevron7. Komunikuje výhradne natívnou správou s aplikáciou, neotvára žiadny port.` |
| `_locales/sk/messages.json` | `Chevron7` and `Podpisovanie na štátnych weboch cez Chevron7.` |
| `popup.html` title and `h1` | `Chevron7` |
| `popup.html` label | `Podpisovať cez Chevron7` |
| `popup.js:19` | `Podpisovanie na tejto stránke preberá Chevron7.` |
| `background.js:29` | `Chevron7 neodpovedal.` |
| `ditec.js:209` | `Spojenie s aplikáciou Chevron7 sa prerušilo. Skúste podpísať znova.` |
| `ditec.js:237` | `Chevron7 neodpovedal. Skontrolujte, či je rozšírenie zapnuté.` |
| `ditec.js:278` | `Chevron7 nie je dostupný.` |

Comments: `background.js:10` "A status request starts Chevron7 when it is not running."; `content.js:5` "after Chevron7 is reinstalled"; `ditec.js:4` "one request for Chevron7". Keep the attribution comments naming `slovensko-digital/autogram-extension` (`ditec.js:6,100`, `inject.js:10`).

- [ ] **Step 3: Verify**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram/WebExtension/dist
command -v node >/dev/null && for f in *.js; do node --check "$f" && echo "$f ok"; done
python3 -m json.tool manifest.json >/dev/null && python3 -m json.tool _locales/sk/messages.json >/dev/null && echo json-ok
rg -n -i 'autogram' . | rg -v 'isAutogram: true|slovensko-digital/autogram-extension|upstream autogram-extension'
grep -c 'isAutogram: true' ditec.js
cd ../.. && scripts/check-rename-boundary.sh
```
Expected: every file `ok`. If `node` is not installed, install nothing: the syntax is then checked in Safari's console during Task 15. Then `json-ok`; the `rg` prints nothing; `1`; boundary holds.

- [ ] **Step 4: Commit**

```bash
git add -A WebExtension
git commit -m "feat(web): call the Safari extension Chevron7 and expose window.chevron7

ditec.isAutogram stays: portals branch on it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Product name in Swift user-facing strings

Slovak does not decline "Chevron7", so inflected forms become "aplikácia Chevron7" in the right case. Every string naming "Autogram v mobile" stays.

**Files:**
- Modify: the lines in the table below; tests found by Step 1.

- [ ] **Step 1: Find tests that pin any of these strings**

Run: `cd Autogram && rg -n 'Elektronický podpis Autogram|Autogram Demo CA|autogram-demo-signature|Autogram ZaKo|Autorizácia dokumentu|nerozumie požiadavke|už spracúva inú|sa v Autograme|Autogram: protokol|autogram-davka|nebeží alebo nie je dostupný|Služba Autogramu|Spojenie s Autogramom|Autogram vrátil|Autogram požiadavku|inštaláciu Autogram|urn:autogram' Tests`
Expected: note each hit; update its expected value in Step 2 to the new text from the table.

- [ ] **Step 2: Replace**

| File:line (under `Autogram/Sources/`) | New value |
| --- | --- |
| `Chevron7App/SigningSessionStore.swift:1515` | `"Elektronický podpis Chevron7"` |
| `Chevron7App/Views/RootView.swift:316` | `.navigationTitle("Chevron7")` |
| `Chevron7App/Views/SettingsView.swift:598` | `Data("chevron7-tsa-connectivity-test".utf8)` |
| `Chevron7App/Views/SettingsView.swift:983` | `"Chevron7 zatiaľ nevytvára samostatný podpísaný záznam, ktorý EZZK prijíma. Záznamy ostávajú v Registri konverzií vo fronte odoslania."` |
| `Chevron7App/Views/SettingsView.swift:1031` | `"Quick Action je samostatné Automator workflow. Spúšťa pomocný program podpisového enginu v pozadí, takže hlavné okno aplikácie sa pri podpise neotvorí."` |
| `Chevron7App/Views/SettingsView.swift:1090` | replace `ukončite a znova spustite Autogram` with `ukončite a znova spustite Chevron7` |
| `Chevron7App/Views/SigningFlowViews.swift:138` | `"Podporované formáty: PDF, JPEG, PNG, TIFF. Chevron7 dokument podpíše kvalifikovaným elektronickým podpisom (KEP) s voliteľnou časovou pečiatkou."` |
| `Chevron7App/Views/SigningFlowViews.swift:1752` | `"chevron7-davka.txt"` |
| `Chevron7App/Views/SigningFlowViews.swift:1769` | `"Chevron7: protokol podpisovania dávky"` |
| `Chevron7App/Views/ZakoFlowViews.swift:149` | replace `Autogram automaticky analyzuje` with `Chevron7 automaticky analyzuje` |
| `Chevron7App/WebBridgeListener.swift:143` | `"Požiadavka na podpis sa v aplikácii Chevron7 nenašla. Skúste podpísať znova."` |
| `Chevron7App/WebSigningCoordinator.swift:40` | `"Chevron7 už spracúva inú požiadavku na podpis."` |
| `Chevron7Kit/EZZK/EZZKService.swift:90` | `"EZZK nerozumie požiadavke aplikácie Chevron7 (\(detail)). Ide o chybu aplikácie."` |
| `Chevron7Kit/PDFA/PDFAConverter.swift:33` | `"PDF/A normalizácia nie je dostupná. Skontrolujte inštaláciu aplikácie Chevron7 a skúste znova."` |
| `Chevron7Kit/PDFA/PDFAConverter.swift:43` | `producer: String = "Chevron7 ZaKo 1.0"` |
| `Chevron7Kit/Signing/PAdESSigner.swift:28` | `reason: String = "Autorizácia dokumentu - Chevron7"` (this also removes an em dash) |
| `Chevron7Kit/Signing/SigningProvider.swift:361` | `issuerSummary: "Chevron7 Demo CA"` |
| `Chevron7Kit/Signing/SigningProvider.swift:390` | `"type": "chevron7-demo-signature"` |
| `Chevron7WebExtensionHandler/main.swift:45` | `"Chevron7 nebeží alebo nie je dostupný."` |
| `Chevron7WebExtensionHandler/main.swift:58` | `"Služba aplikácie Chevron7 nie je dostupná: \(error.localizedDescription)"` |
| `Chevron7WebExtensionHandler/main.swift:77` | `"Spojenie s aplikáciou Chevron7 zlyhalo: \(error.localizedDescription)"` |
| `Chevron7WebExtensionHandler/main.swift:106,139` | `"Chevron7 vrátil prázdnu odpoveď."` |
| `Chevron7WebExtensionHandler/main.swift:119` | `error ?? "Chevron7 požiadavku na podpis neprijal."` |
| `webbridge-probe/main.swift:40` | `"Agent beží, ale Chevron7 sa nepodarilo spustiť ani po 20 s.\n"` |
| `webbridge-probe/main.swift:117` | `print("Chevron7     : \(version)")` |
| `avm-probe/main.swift:25` | `xmlns="urn:chevron7:avm-probe:sample"` |

Unchanged on purpose: `SigningSessionStore.swift:365`, `MobileSigningSheet.swift:16`, `SettingsView.swift:1408,1413`, `SigningFlowViews.swift:795`, `WebSigningSheet.swift:171`, `AVMModels.swift`, `AVMResultMapper.swift` (Autogram v mobile), `EngineBridgeSigningProvider.swift:722` (names the engine's `AutogramCLI` helper).

Also sweep comments that call the product Autogram, for example `Chevron7App.swift:177` ("person opens Chevron7 themselves"):

Run: `rg -n '\bAutogram\b' Sources Tests -g '*.swift' | rg -v 'Autogram v mobile|AutogramCLI|autogram\.slovensko|org\.autogram|digital\.slovensko\.autogram|slovensko-digital/autogram'`
Expected after the edits: only comments that describe the upstream project or the engine (for example "fork of Autogram"), plus test fixtures such as `ValidationAndPAdESTests.swift:237` (`"Autogram Test"` certificate name, harmless). Change any that call this app Autogram, for example `WebBridgeEndpointRegistryTests.swift:7`.

- [ ] **Step 3: Verify**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift test 2>&1 | tail -3
rg -n '\x{2014}' Sources Tests | head
scripts/check-rename-boundary.sh
```
Expected: 0 failures; the em dash search prints nothing new that this task introduced; boundary holds.

- [ ] **Step 4: Commit**

```bash
git add -A Sources Tests
git commit -m "feat: say Chevron7 wherever the app names itself

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Licensing and attribution

**Files:**
- Create: `LICENSE` (repository root), `Autogram/LICENSE`, `NOTICE`
- Modify: `Autogram/build_app.sh` (`NSHumanReadableCopyright`), every `*.swift` under `Autogram/Sources` and `Autogram/Tests`, every `*.sh` under `Autogram/scripts` and `Autogram/build_app.sh`, the workflow scripts, `Autogram/WebExtension/dist/*.js`
- Unchanged: `engine/LICENSE` and everything else in `engine/`

- [ ] **Step 1: Licence files**

```bash
cd /Users/magneto/Projects/Autogram-macOS
cp engine/LICENSE LICENSE
cp engine/LICENSE Autogram/LICENSE
cmp LICENSE engine/LICENSE && echo same
```

`NOTICE`:
```
Chevron7
Copyright 2026 Marián Čuprík

Licensed under the European Union Public Licence v. 1.2 (EUPL-1.2), see LICENSE.

This repository holds two works under the same licence:

- Chevron7/ (the macOS application, its web extension and scripts):
  copyright Marián Čuprík, EUPL-1.2.
- engine/ (the signing engine): a fork of slovensko-digital/autogram,
  copyright its authors, EUPL-1.2, see engine/LICENSE. It runs as a separate
  process with its own Java runtime and talks to the application over the
  Autogram machine protocol.

Chevron7/WebExtension/dist/ditec.js and inject.js port parts of
slovensko-digital/autogram-extension (EUPL-1.2).

Signing with a phone over NFC uses the Autogram v mobile application and the
relay at autogram.slovensko.digital, both run by Slovensko.Digital.

Chevron7 is not affiliated with or endorsed by Slovensko.Digital, and not
affiliated with Chevron Corporation.
```
The folder is still `Autogram/` until Task 11; the NOTICE already names it `Chevron7/` so it does not need a second edit.

In `Autogram/build_app.sh` replace the `NSHumanReadableCopyright` value so the bundle credits its author and licence:

```xml
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Marián Čuprík, EUPL-1.2. Podpisový engine: fork slovensko-digital/autogram.</string>
```

- [ ] **Step 2: SPDX headers**

Header for files written for this project:
```
SPDX-FileCopyrightText: 2026 Marián Čuprík
SPDX-License-Identifier: EUPL-1.2
```
For `ditec.js` and `inject.js` add a second copyright line above the licence line: `SPDX-FileCopyrightText: Slovensko.Digital and contributors to autogram-extension`.

The session shell may be zsh, so run the block through bash explicitly:

```bash
cd /Users/magneto/Projects/Autogram-macOS/Autogram
bash <<'EOF'
set -euo pipefail
add_header() { # file comment-prefix
  local f="$1" c="$2"
  grep -q 'SPDX-License-Identifier' "$f" && return 0
  local extra=""
  case "$f" in *ditec.js|*inject.js) extra="$c SPDX-FileCopyrightText: Slovensko.Digital and contributors to autogram-extension"$'\n' ;; esac
  local header="$c SPDX-FileCopyrightText: 2026 Marián Čuprík"$'\n'"${extra}$c SPDX-License-Identifier: EUPL-1.2"$'\n'
  if head -1 "$f" | grep -q '^#!'; then
    { head -1 "$f"; printf '%s' "$header"; tail -n +2 "$f"; } > "$f.tmp"
  else
    { printf '%s\n' "$header"; cat "$f"; } > "$f.tmp"
  fi
  chmod "$(stat -f %Lp "$f")" "$f.tmp"
  mv "$f.tmp" "$f"
}
while IFS= read -r -d '' f; do add_header "$f" "//"; done < <(find Sources Tests -name '*.swift' -print0)
while IFS= read -r -d '' f; do add_header "$f" "//"; done < <(find WebExtension/dist -name '*.js' -print0)
for f in build_app.sh scripts/*.sh Assets/*.workflow/Contents/Resources/*.sh; do add_header "$f" "#"; done
EOF
```

- [ ] **Step 3: Verify**

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
find Sources Tests -name '*.swift' | xargs grep -L 'SPDX-License-Identifier: EUPL-1.2' | head
for f in build_app.sh scripts/*.sh; do bash -n "$f" || echo "BROKEN $f"; done
head -3 build_app.sh scripts/check-rename-boundary.sh
git diff --stat -- ../engine | tail -1
swift build 2>&1 | tail -1 && swift test 2>&1 | tail -3
scripts/check-rename-boundary.sh
```
Expected: no file listed; no `BROKEN`; each script still starts with `#!/bin/bash`; the engine diff is empty; build and tests green; boundary holds.

- [ ] **Step 4: Commit**

```bash
cd /Users/magneto/Projects/Autogram-macOS
git add LICENSE NOTICE Autogram/LICENSE Autogram
git commit -m "docs: license Chevron7 under EUPL-1.2 and credit the Autogram projects

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Living documentation

**Files:**
- Modify: `README.md`, `AGENTS.md`, `CLAUDE.md`, `Autogram/docs/EZZK-INTEGRATION.md`, `Autogram/docs/security-element-training.md`, `.gitignore`
- Unchanged: every historical document listed in Global Constraints

- [ ] **Step 1: README**

Near the top, directly under the title, add:

```markdown
## Pôvod a poďakovanie

Chevron7 je natívna macOS aplikácia na kvalifikovaný elektronický podpis a zaručenú konverziu. Podpisový engine v priečinku `engine/` je fork projektu [slovensko-digital/autogram](https://github.com/slovensko-digital/autogram) pod licenciou EUPL 1.2. Podpisovanie mobilom cez NFC používa aplikáciu Autogram v mobile a server autogram.slovensko.digital, ktoré prevádzkuje Slovensko.Digital. Rozšírenie pre Safari preberá časti [slovensko-digital/autogram-extension](https://github.com/slovensko-digital/autogram-extension).

Chevron7 nie je spojený so Slovensko.Digital ani ním podporovaný a nemá nič spoločné so spoločnosťou Chevron Corporation. Licencia: EUPL 1.2, pozri `LICENSE` a `NOTICE`.
```

Then replace the product name, paths and identifiers throughout: `Autogram macOS` → `Chevron7`, `/Applications/Autogram macOS.app` → `/Applications/Chevron7.app`, `sk.autogram.*` → the `app.slovensko.chevron7.*` names from Global Constraints, `AUTOGRAM_ENGINE_LIVE_TEST` → `CHEVRON7_ENGINE_LIVE_TEST`, `window.autogramMacOS` → `window.chevron7`, module names per Global Constraints. Remove the known limitation about the `autogram://` scheme collision; it no longer applies. Keep every sentence about the engine fork, Autogram v mobile, `autogram.slovensko.digital` and the official Autogram extension.

- [ ] **Step 2: AGENTS.md and CLAUDE.md**

Edit `CLAUDE.md`, then `cp CLAUDE.md AGENTS.md`. Changes:
- Title `# AGENTS.md - Chevron7 macOS UI`; overview "Chevron7 is a 100% native macOS SwiftUI application ... Its signing engine is a fork of slovensko-digital/autogram (see NOTICE)."
- Keychain `sk.autogram.Autogram.ezzk.soap` → `app.slovensko.chevron7.ezzk.soap`; `AUTOGRAM_DIAG_PDF` → `CHEVRON7_DIAG_PDF` (`AUTOGRAM_JAVA_HOME` stays); `~/Library/Application Support/Autogram/VisionBank` → `~/Library/Application Support/Chevron7/VisionBank`; binary output `$(swift build --show-bin-path)/Chevron7.app` and `.build/out/Products/Debug/Chevron7.app`; `bundles into Autogram macOS.app` wording wherever it appears.
- Add under Architecture: "Rename boundary: `scripts/check-rename-boundary.sh [--strict]` guards what keeps the Autogram name (AVM relay, engine, `org.autogram.asice`, machine protocol, `ditec.isAutogram`, FormPack id). Design: `docs/superpowers/specs/2026-09-22-chevron7-rename-design.md`."
- Paths stay `Autogram/...` in this task; Task 11 changes them.

- [ ] **Step 3: Other living docs**

`Autogram/docs/EZZK-INTEGRATION.md`: the Keychain service name and any app path. `Autogram/docs/security-element-training.md`: the VisionBank path and product name. `.gitignore`: nothing yet (Task 11).

- [ ] **Step 4: Verify**

```bash
cd /Users/magneto/Projects/Autogram-macOS
cmp AGENTS.md CLAUDE.md && echo in-sync
rg -c '\x{2014}' README.md AGENTS.md CLAUDE.md Autogram/docs/EZZK-INTEGRATION.md Autogram/docs/security-element-training.md NOTICE
Autogram/scripts/check-rename-boundary.sh --strict
```
Expected: `in-sync`; the em dash search prints nothing; `✔ Boundary holds` in strict mode. The strict pattern does not look at `Autogram/` folder paths, which Task 11 changes, so any hit here is a real leftover to fix.

- [ ] **Step 5: Commit**

```bash
git add README.md AGENTS.md CLAUDE.md Autogram/docs/EZZK-INTEGRATION.md Autogram/docs/security-element-training.md
git commit -m "docs: describe the product as Chevron7 and credit its origins up front

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Package folder `Autogram/` → `Chevron7/`

**Files:**
- Move: `Autogram/` → `Chevron7/` (tracked files via `git mv`, the ignored `.build` by `mv`)
- Modify: `.gitignore`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `Autogram/scripts/build-engine.sh:6-7` (comment), `Autogram/docs/EZZK-INTEGRATION.md` and any other living doc that names `Autogram/`

- [ ] **Step 1: Move, keeping the engine build**

```bash
cd /Users/magneto/Projects/Autogram-macOS
git mv Autogram Chevron7
[ -d Autogram/.build ] && mv Autogram/.build Chevron7/.build
find Autogram -name .DS_Store -delete 2>/dev/null; rmdir Autogram 2>/dev/null; ls -d Autogram 2>/dev/null || echo "old folder gone"
ls Chevron7/.build/engine/Contents/Helpers/AutogramCLI-arm64
```
Expected: `old folder gone`; the engine helper exists. If `rmdir` leaves something behind, list it and stop.

- [ ] **Step 2: Fix the paths**

`.gitignore`: `Autogram/.build/` → `Chevron7/.build/`.
`Chevron7/scripts/build-engine.sh` comment: `# Output: Chevron7/.build/engine/Contents/{Helpers,app,runtime}, which` and `# build_app.sh bundles into Chevron7.app.`
Living docs: replace path prefixes `Autogram/docs/`, `Autogram/Sources/`, `Autogram/scripts/`, `Autogram/Tests/`, `Autogram/WebExtension/`, `Autogram/Assets/`, `Autogram/build_app.sh` with `Chevron7/...` in `README.md`, `CLAUDE.md` (then `cp CLAUDE.md AGENTS.md`), `Chevron7/docs/EZZK-INTEGRATION.md`, `Chevron7/docs/security-element-training.md`. In `CLAUDE.md` also fix the design links that already point at `Autogram/docs/...`.

```bash
perl -pi -e 's#\bAutogram/(docs|Sources|scripts|Tests|WebExtension|Assets|build_app\.sh|Package\.swift|LICENSE)#Chevron7/$1#g' README.md CLAUDE.md Chevron7/docs/EZZK-INTEGRATION.md Chevron7/docs/security-element-training.md
cp CLAUDE.md AGENTS.md
```

- [ ] **Step 3: Strict verification**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Chevron7
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift build 2>&1 | tail -1
swift test 2>&1 | tail -3
./build_app.sh --release 2>&1 | tail -2
scripts/check-rename-boundary.sh --strict
cd .. && cmp AGENTS.md CLAUDE.md && echo in-sync
git grep -n 'Autogram/' -- README.md AGENTS.md CLAUDE.md Chevron7/docs/EZZK-INTEGRATION.md Chevron7/docs/security-element-training.md .gitignore
```
Expected: build and tests green (baseline + new tests, 0 failures); release bundle built; `✔ Boundary holds` in strict mode; `in-sync`; the last grep prints nothing (references such as `slovensko-digital/autogram` are not matched because they are lower case).

- [ ] **Step 4: Commit**

```bash
git add -A .gitignore README.md AGENTS.md CLAUDE.md Chevron7 Autogram
git commit -m "refactor: move the package folder to Chevron7/

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

This plan now lives at `Chevron7/docs/superpowers/plans/2026-09-22-chevron7-rename.md`; read it from there for the remaining tasks.

Phase A ends here. The installed system is still the old Autogram macOS and still works.

---

# Phase B: this Mac and GitHub

Every task here changes the system or publishes. Before each one, show the user the exact commands and wait for a clear yes in chat.

### Task 12: Tear down the old install

- [ ] **Step 1: Ask the user to quit Safari (⌘Q) and the running app.** Confirm with `pgrep -x Safari; pgrep -f "/Applications/Autogram macOS.app/"` printing nothing. Match by path, not by process name: the official `/Applications/Autogram.app` (bundle `digital.slovensko.autogram`) also runs an executable named `Autogram`, and `pgrep -x Autogram` would match it too. The official apps may keep running; only our own `Autogram macOS.app` needs to be quit here.

- [ ] **Step 2: Back up the old settings (non-destructive)**

```bash
BACKUP="$HOME/Documents/Chevron7-migration-2026-09-22"
mkdir -p "$BACKUP"
defaults export sk.autogram.Autogram "$BACKUP/sk.autogram.Autogram.plist"
ls -l "$BACKUP"
```

- [ ] **Step 3: Remove the agent, extension and app (to the Trash, not deleted)**

`/Applications` also holds the official `Autogram.app` (`digital.slovensko.autogram`) and `Autogram na štátnych weboch.app` (slovensko.digital). Only our own `Autogram macOS.app` (`sk.autogram.Autogram`) goes to the Trash below; leave the other two in place.

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
launchctl bootout "gui/$(id -u)/sk.autogram.Autogram.webbridge" 2>/dev/null || true
mv "$HOME/Library/LaunchAgents/sk.autogram.Autogram.webbridge.plist" "$HOME/.Trash/" 2>/dev/null || true
pluginkit -r "/Applications/Autogram macOS.app/Contents/PlugIns/AutogramWebExtension.appex" 2>/dev/null || true
"$LSREGISTER" -u "/Applications/Autogram macOS.app"
mv "/Applications/Autogram macOS.app" "$HOME/.Trash/"
mv "$HOME/Library/Services/Autogram Finder Quick Action.workflow" "$HOME/.Trash/" 2>/dev/null || true
/System/Library/CoreServices/pbs -flush
```

- [ ] **Step 4: Unregister every stale copy LaunchServices still knows**

```bash
mdfind 'kMDItemCFBundleIdentifier == "sk.autogram.Autogram"'
```
For each path printed, run `"$LSREGISTER" -u "<path>"`; then, only for a regenerable build product, remove that `.app` folder. Known stale registrations as of this review: the build products `Chevron7/.build/out/Products/{Debug,Release}/Autogram.app` and `Chevron7/.build/arm64-apple-macosx/{debug,release}/Autogram.app` (unregister and delete, they are regenerable); the release artifact `Chevron7/.build/releases/v0.4.0/staging/Autogram macOS.app` (unregister only, do not delete); and a copy under `/private/var/folders/.../T/autogram-before-ui-merge-*/Autogram macOS.app` (unregister only; ask the user before deleting anything outside this repository). Use `"$LSREGISTER" -dump | grep -B5 sk.autogram.Autogram` to find any further paths.

- [ ] **Step 5: Verify nothing old remains**

```bash
launchctl print "gui/$(id -u)/sk.autogram.Autogram.webbridge" 2>&1 | head -1
pluginkit -m -i sk.autogram.Autogram.WebExtension -vvv
"$LSREGISTER" -dump | grep -c 'sk.autogram.Autogram'
```
Expected: `Could not find service`; no pluginkit output; a count of `0` (if not 0, repeat Step 4 for the paths `lsregister -dump | grep -B5 sk.autogram.Autogram` shows).

### Task 13: Copy the data into `Chevron7`

- [ ] **Step 1: Copy, do not move**

```bash
OLD="$HOME/Library/Application Support/Autogram"
OLD_VS="$HOME/Library/Application Support/Autogram macOS/Visual Signatures"
NEW="$HOME/Library/Application Support/Chevron7"
if [ -n "$(find "$NEW" -type f 2>/dev/null | head -1)" ]; then
  echo "Chevron7 already has files, stop and ask the user"
else
  ditto "$OLD" "$NEW"
  if [ -d "$OLD_VS" ]; then ditto "$OLD_VS" "$NEW/Visual Signatures"; fi
fi
```
The guard checks for any regular file under `$NEW`, not just its existence: `swift test` already creates an empty `~/Library/Application Support/Chevron7/Evidence` folder (and files under `~/Library/Caches/Chevron7`) because app tests construct their stores against the real Application Support folder rather than a temporary one (deferred follow-up: inject a temp folder for tests). `ditto` merges into an existing empty folder without complaint, so an empty `$NEW` should not stop this step. Do not run `swift test` between this task and Task 15, or its Evidence writes could be mistaken for real data.

- [ ] **Step 2: Verify byte for byte**

```bash
diff -r "$OLD" "$NEW" | grep -v '^Only in .*Chevron7: Visual Signatures$'
[ -d "$OLD_VS" ] && diff -r "$OLD_VS" "$NEW/Visual Signatures"
if [ -f "$OLD/Evidence/register.json" ]; then shasum -a 256 "$OLD/Evidence/register.json" "$NEW/Evidence/register.json"; else echo "no evidence register on this Mac"; fi
grep -rl "Application Support/Autogram" "$NEW" | head
```
Expected: no diff output; identical register hashes, or `no evidence register on this Mac` (the case on 2026-09-22: `Evidence/` was empty); the last `grep` prints nothing (on 2026-09-22 no stored file held an absolute path to the old folder). If it prints a file, stop: its paths need a one-off rewrite from `Autogram/` to `Chevron7/`, agreed with the user first.

The old folders stay in place as the backup until Task 15 has confirmed the register opens. Then the user decides whether to move them to the Trash.

### Task 14: Build, install and register Chevron7

- [ ] **Step 1: Build and install**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Chevron7
[ -x .build/engine/Contents/Helpers/AutogramCLI-arm64 ] || scripts/build-engine.sh
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" ./build_app.sh --release install
scripts/install-webbridge-agent.sh
open /Applications/Chevron7.app
```

- [ ] **Step 2: Hand the Safari steps to the user**

Tell the user: open Safari, Develop > Allow Unsigned Extensions, Settings > Extensions > enable "Chevron7", then re-enter the EZZK password and any AI provider API keys in Chevron7 Settings. Also tell the user to disable the official Safari extension "Autogram na štátnych weboch" (`digital.slovensko.autogram.autogram-extension`), at least on the state portals: it also defines a non-configurable `window.ditec`, and whichever content script runs first wins. Ditec D.Bridge 2 can conflict the same way (see memory note safari-signing-env-conflicts).

### Task 15: Verification

- [ ] **Step 1: Run each check and record the output**

```bash
cd /Users/magneto/Projects/Autogram-macOS/Chevron7
pluginkit -m -i app.slovensko.chevron7.WebExtension -vvv
```
Expected: `Path = /Applications/Chevron7.app/Contents/PlugIns/Chevron7WebExtension.appex`. The `-vvv` is required.

```bash
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -dump | grep -E '^path: .*Chevron7\.app' | sed -E 's/ \(0x[0-9a-f]+\)$//' | sort -u
"$LSREGISTER" -dump | grep -c 'sk.autogram.Autogram'
```
Expected: only `/Applications/Chevron7.app` and paths inside it (the appex); count `0`. A path under `.build/` means a build product is still registered: `"$LSREGISTER" -u "<that path>"` and run the check again.

```bash
scripts/check-rename-boundary.sh --strict
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test 2>&1 | tail -3
scripts/safari-spike.sh
```
Expected: boundary holds; 0 failures; step 6 of the spike reports a working XPC transport.

```bash
swift run avm-probe <any small PDF> --timeout 120
```
Expected: a QR link on `autogram.slovensko.digital`; the user signs on the phone; signers are printed. This is the regression test for the NFC path.

- [ ] **Step 2: Checks only the user can do**

- In Safari on `https://www.slovensko.sk/`, console: `await window.chevron7.status()` returns `{ ok: true, ready: true, version: "0.4.0" }`, and `window.ditec.isChevron7 === true` (the official extension also sets `isAutogram`, so that flag alone would not distinguish ours).
- In Chevron7, Register konverzií lists every record it listed before the rename.
- Drag a PDF onto Podpisovanie and sign it: the signed copy lands next to the original (the fix from `db1b76df`).
- Finder Quick Action "Podpísať s QES + QTS (Chevron7)" appears for a PDF.

### Task 16: Merge, push and rename on GitHub

- [ ] **Step 1: Merge** using superpowers:finishing-a-development-branch (merge `rename/chevron7` into `main`).

- [ ] **Step 2: Push** `main` to `origin` after the user's yes.

- [ ] **Step 3: Rename the repository** after the user's yes:

```bash
gh repo rename chevron7 --repo originalmagneto/autogram-macOS --yes
git remote set-url origin https://github.com/originalmagneto/chevron7.git
git fetch origin && git status -sb | head -1
```

Do not create a placeholder repository under the old name. GitHub redirects the old URL to the renamed repository only while no repository takes the old name; a placeholder would end those redirects, which is the opposite of what the spec intends. The spec's step 4 is corrected here on purpose.

- [ ] **Step 4: Update the README links that still point at the old repository slug**, after the rename: the release badge link and image near line 8 and the download link near line 404, all `originalmagneto/autogram-macOS` to `originalmagneto/chevron7`. Commit and push after the user's yes.

### Task 17 (optional, user decides): Local folder and Claude memory

Only if the user wants the working copy renamed:

```bash
mv /Users/magneto/Projects/Autogram-macOS /Users/magneto/Projects/Chevron7
mv "$HOME/.claude/projects/-Users-magneto-Projects-Autogram-macOS" "$HOME/.claude/projects/-Users-magneto-Projects-Chevron7"
```
Then update the `chevron7-rename` memory to say the rename shipped, and open the next session in the new folder.

---

## Known residue, recorded so nobody "fixes" it

- The engine still writes `Producer: Autogram macOS` into PDF/A output it normalizes when the source has no producer, and its Quick Action runner says "Pomocný program Autogram macOS". Changing either means editing `engine/`, which the boundary forbids; a later upstream-style patch can make the producer a parameter.
- `PDFAValidator` looks for `Autogram PDFBox`, a producer nothing writes any more. It is a record-format check and stays until someone confirms no stored document carries it.
- The application icon (`Chevron7.icns`) is the old artwork under a new file name. The spec requires an original icon; that is a design task of its own.
- `Assets/AppIcon.iconset` is unused by any build step.

## Out of scope

Multi-country eID support and the Stripe side of donations, as in the spec.
