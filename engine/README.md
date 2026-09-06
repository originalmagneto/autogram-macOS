# Autogram signing engine

Fork of [slovensko-digital/autogram](https://github.com/slovensko-digital/autogram) (EUPL 1.2, see `LICENSE`) trimmed to what the native macOS app needs: the DSS signing core, PKCS#11 drivers, and the headless machine protocol (`src/main/java/digital/slovensko/autogram/ui/machine`, `protocol/v1`, `protocol/v2`, `docs/machine-cli-protocol-v1.md`).

The native app talks to it in two ways:

- `AutogramCLI-arm64` (`scripts/native-macos/autogram-cli-launcher.c`) starts the bundled jlink runtime with protocol v1 for the Finder Quick Action runner (`scripts/native-macos/autogram-quick-action-runner.swift`).
- `EngineBridgeSigningProvider` in AutogramKit runs `runtime/bin/java -jar app/autogram.jar --cli --machine-readable --protocol-version 2` directly.

Build it with `Autogram/scripts/build-engine.sh`; it needs an arm64 JDK 25 with JavaFX jmods (Azul Zulu FX 25) and writes `Autogram/.build/engine/Contents/{Helpers,app,runtime}`, which `Autogram/build_app.sh` bundles into the app. `target/` is build output and is git-ignored.

Machine mode ends its own process with SIGKILL after the terminal event is flushed (PKCS#11 teardown can hang), so exit status 137 after `session.completed` is normal.
