# Autogram
[🇸🇰 Slovenská verzia](README-SK.md)

Autogram is a desktop app for signing and verifying documents (eIDAS compliant) on macOS, Windows, and Linux.
It supports GUI workflows, CLI usage, and local HTTP API integration.

![Screenshot](assets/autogram-screenshot-en.png?raw=true)

## What You Get

- Native desktop application (JavaFX)
- Document signing and signature validation
- Local HTTP API for integration with web/information systems
- CLI mode for batch signing
- PKCS#11 token support + selected native card integrations

## Download and Install

Use packages from [GitHub Releases](../../releases):

- macOS: `.dmg` (recommended) or `.pkg`
- Windows: `.msi`/`.exe`
- Linux: `.deb`/`.rpm`

### macOS quick start

1. Download latest `.dmg` from [Releases](../../releases).
2. Open the DMG and drag **Autogram.app** to **Applications**.
3. Launch Autogram from Applications.

## Run Locally (Developers)

### Prerequisites

- JDK 24 with JavaFX (Liberica JDK with FX recommended)
- Maven (or Maven Wrapper `./mvnw`)

### Build

```bash
./mvnw -Psystem-jdk -DskipTests package
```

macOS artifacts are produced in `target/` (typically `.dmg`, `.pkg`, and `app-image/Autogram.app`).

### Run from classes

```bash
./mvnw -Psystem-jdk -DskipTests compile dependency:copy-dependencies
java -cp "target/classes:target/dependency/*" digital.slovensko.autogram.Main
```

### macOS QA helper scripts

```bash
./scripts/macos-update-check.sh
./scripts/macos-ui-smoke.sh
```

## Integration

- Local API docs after startup: `http://localhost:37200/docs`
- OpenAPI file: `src/main/resources/digital/slovensko/autogram/server/server.yml`
- URL handler protocol: `autogram://go`

## Supported Signature Types

- PAdES (PDF)
- XAdES (XML)
- CAdES (binary)
- eForms

## Supported Cards and Tokens

- Any PKCS#11-compatible card/token (with configured driver path)
- Native support for selected cards (e.g., Slovak eID, Czech eObčanka, I.CA SecureStore, MONET+ ProID+Q, Gemalto IDPrime 940)

## Releases for macOS Maintainers

This repository includes a workflow that publishes releases with macOS `.dmg` and `.pkg`:

- file: `.github/workflows/package.yaml`
- triggers:
1. push tag `v*.*.*`
2. manual run via `workflow_dispatch`

To publish:

1. Push a tag, e.g. `v1.2.3`
2. GitHub Actions builds on macOS and creates a GitHub Release with installers attached

## License

Licensed under **EUPL v1.2**.

Originally derived from Octosign White Label (MIT) with author permission for EUPL distribution.
See [LICENSE](LICENSE) for the full text.
