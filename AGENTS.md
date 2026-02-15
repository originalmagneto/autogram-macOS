# Autogram - Agent Instructions

## Project Overview
- **Project**: Autogram - Multi-platform (Windows, macOS, Linux) desktop JavaFX application for signing and verifying documents according to eIDAS regulation
- **Language**: Java 22+ with JavaFX 22
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

# Install Liberica JDK 24 with JavaFX
sdk install java 24.0.2.fx-librca

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

2. **JDK Caching**: The `mvn-jlink-wrapper` plugin may fail when downloading JDK. Use `-Psystem-jdk` profile to use system JDK instead.

3. **JavaFX Dependencies**: JavaFX modules are required. Install Liberica JDK which includes JavaFX, or add JavaFX SDK to classpath.

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
