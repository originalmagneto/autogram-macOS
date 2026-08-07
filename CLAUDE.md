# Autogram - Agent Instructions

## Project Overview
- **Project**: Autogram - Multi-platform (Windows, macOS, Linux) desktop JavaFX application for signing and verifying documents according to eIDAS regulation
- **Language**: Java 25 with JavaFX
- **Build System**: Maven
- **Environment Warning**: This is a **native desktop Java application**. It **cannot** be previewed or interacted with through a web browser (e.g., Chrome). All visual testing must be done by running the actual application on the host system.
- **Main Class**: `digital.slovensko.autogram.Main`

## Prerequisites

### JDK Installation (macOS)
The project requires Liberica JDK with JavaFX. Install using SDKMAN:
```bash
# Install SDKMAN (if not installed)
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"

# Install Liberica JDK 25 with JavaFX
sdk install java 25.0.4.fx-librca

# Verify installation
java -version
```

## Build Commands
```bash
# Source SDKMAN (in each new terminal)
source "$HOME/.sdkman/bin/sdkman-init.sh"
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

# Development build (compile only)
./mvnw compile -Psystem-jdk -DskipTests

# Full build with dependencies (Create macOS .app)
./mvnw package -Psystem-jdk -DskipTests
# Note: On macOS, this generates target/app-image/Autogram.app

# Build with tests
./mvnw test -Psystem-jdk
```

## Running the App
```bash
# Option 1: Run directly from compiled classes
java -cp "target/classes:target/dependency/*" digital.slovensko.autogram.Main

# Option 2: Run the built app bundle
open target/app-image/Autogram.app

# Option 3: Install from pkg
open target/Autogram-1.0.0.pkg
```

## Known Issues & Fixes

1. **SeparatorMenuItem FXML Error**: In JavaFX 22+, you must explicitly import `SeparatorMenuItem` in FXML files:
   ```xml
   <?import javafx.scene.control.SeparatorMenuItem?>
   ```
   Fixed in: `src/main/resources/digital/slovensko/autogram/ui/gui/main-menu.fxml`

2. **JDK Caching**: The default build caches BellSoft JDK 25 with JavaFX. Use `-Psystem-jdk` only with a local JDK 25 that also provides JavaFX modules.

3. **JavaFX Dependencies**: JavaFX modules are required for both compilation and jlink packaging. Install Liberica JDK 25 with JavaFX, or use the Maven JavaFX dependencies for compilation and a JavaFX-capable runtime for packaging.

4. **macOS-specific**: The app uses `com.apple.eawt` APIs for menu bar integration which may not work on all JDK versions.

## Key Files

- `src/main/java/digital/slovensko/autogram/Main.java` - Entry point
- `src/main/java/digital/slovensko/autogram/core/AppStarter.java` - CLI/GUI mode selection
- `src/main/java/digital/slovensko/autogram/ui/gui/MainMenuController.java` - Main window orchestrator (overlays, panels)
- `src/main/java/digital/slovensko/autogram/ui/gui/GUIApp.java` - JavaFX application
- `pom.xml` - Maven configuration

## Architecture

- **Core**: Document signing, validation, batch processing
- **UI**: JavaFX-based Single-Window GUI with inline overlays, using macOS 'Liquid Glass' design system (transparency, blurs)
- **Server**: Embedded HTTP server for API integration
- **Drivers**: PKCS#11, PKCS#12, and custom token driver support

## Design System

The application follows a **macOS-native "Liquid Glass"** aesthetic.

- **Variables**: Defined in `macos-native.css` (root) and `macos-native-dark.css` (dark mode overrides).
- **Glassmorphism**: Extensive use of translucency, blurs (`-fx-effect: dropshadow(...)`), and subtle borders (`rgba(0,0,0,0.1)`).
- **Overlays**: Dialogs are rendered as inline overlays within the main window using `StackPane` and `MainMenuController.showOverlayDialog()`.
    - Use `.autogram-overlay-card` for dialog containers.
    - Use `.autogram-dialog-content` for inner padding.
- **Typography**: System fonts (San Francisco) via `-fx-font-family: "System"`.

## Supported Signature Types

- PAdES (PDF)
- XAdES (XML)
- CAdES (Binary)
- eForms (Slovak government forms)

# MSW — the kernel

Remember to follow the MSW deletion rule for all claims - no exceptions.

## program — complete

```
contract ← the requested outcome + the smallest criteria that prove it

while ∃ claim c : deleting c leaves contract unmet ∨ unproven
      do c ; prove c

halt ; report
```

## definitions — no behavior lives here, only meaning

**contract** — the requested outcome and the smallest set of acceptance criteria that would prove it, stated before any work. The sole source of necessity; a ceiling as much as a floor. If the request is ambiguous: attended → ask; unattended → bind the smallest reading consistent with stated intent and record the assumption.

**claim** — anything petitioning to become work: a plan step, a change, a test, a reviewer's P1, a discovered edge case, your own instinct that one more pass would help. Everything enters as this type. Nothing enters as a verdict.

**deleting c leaves contract unmet ∨ unproven** — the only test. A claim passes solely by breaking the contract — reproducibly, within the task's actual inputs and environment. Severity is derived from the contract, never inherited from whoever raised the claim. *Useful*, *thorough*, and *possible* are not aliases for *necessary*. A claim that fails receives one line in the report — never a fix, an investigation, or a deferred follow-up.

**do ; prove** — the smallest reliable act that closes the gap, and evidence sized to the claim it settles. An unproven act keeps its claim alive; a proven one closes it — and re-proving a closed claim is itself an inadmissible claim.

**halt** — the fixed point: contract proven, no remaining claim passes. Not reviewer silence; not exhausted imagination. Halting before the fixed point and looping past it are the same bug, mirrored.

**report** — the outcome against the contract; the proof; rejected claims worth the user's attention, one line each. Nothing else.

## fuses — outside the program, for when its evaluator fails

```
rounds = 3            → halt anyway ; report open items, do not chase them
claim born in round n+1, visible in round n   → rejected
```

## No unauthoritative limits

Never invent a limit. A cap, threshold, quota, budget, timeout, retry or round count, file or line count, acceptance-criterion count, agent count, or similar constraint is admissible only when its exact value is:

- explicitly required by the requester;
- imposed by an applicable technical or platform contract;
- defined by authoritative project policy; or
- derived from measured evidence necessary to meet or prove the task contract.

State the authority or derivation whenever proposing or applying a limit. If no authority exists, omit the limit and use the MSW necessity test. Metrics may be reported as evidence, but they must not become gates, defaults, targets, or recommendations through agent intuition. Examples and representative proportions never become defaults. If a necessary limit is an unresolved owner choice, ask; do not manufacture a value.
