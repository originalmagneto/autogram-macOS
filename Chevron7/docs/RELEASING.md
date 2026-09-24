# Chevron7 release signing, notarization, and Sparkle

Chevron7 is distributed directly as a Developer ID signed and Apple-notarized macOS application. Sparkle 2 provides in-app updates from GitHub Releases.

## One-time GitHub configuration

Configure these **Actions secrets**:

- `DEVELOPER_ID_APPLICATION_P12`: base64 of the exported Developer ID Application certificate + private key (.p12).
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: password of that .p12.
- `APPLE_API_KEY_P8`: base64 of an App Store Connect API key (.p8) that can use the notarization service.
- `APPLE_API_KEY_ID`: App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID.
- `SPARKLE_PRIVATE_ED_KEY`: the private Ed25519 key exported by Sparkle's `generate_keys` tool.

Configure this **Actions repository variable**:

- `SPARKLE_PUBLIC_ED_KEY`: the base64 public key printed by Sparkle's `generate_keys` tool.

The private Sparkle key and Apple credentials must never be committed to the repository.

## Generate the Sparkle key pair

Use Sparkle's bundled `generate_keys` tool once. It stores the key in the macOS Keychain and prints the public key for `SUPublicEDKey`.

Export a CI copy with the tool's `-x` option and store the exported private-key contents in the `SPARKLE_PRIVATE_ED_KEY` GitHub Actions secret. Keep an offline backup as well.

The release build injects the public key into `Info.plist`. Local builds without `SPARKLE_PUBLIC_ED_KEY` deliberately leave Sparkle dormant.

## Feed

Production builds use:

```text
https://github.com/originalmagneto/chevron7/releases/latest/download/appcast.xml
```

Every release uploads:

- `Chevron7-vX.Y.Z.dmg`
- `SHA256SUMS.txt`
- `appcast.xml`

The appcast points to the immutable versioned DMG under the corresponding `native-vX.Y.Z` GitHub release and contains Sparkle's Ed25519 signature.

## Release pipeline

`.github/workflows/release.yml` performs:

1. build the Java signing engine;
2. build Chevron7 with Sparkle 2 embedded and the public update key injected;
3. re-sign Sparkle's nested updater components with Developer ID;
4. sign all other Mach-O payloads, the Safari Web Extension, and Chevron7.app with Hardened Runtime;
5. submit Chevron7.app to Apple's notarization service and staple the ticket;
6. package the stapled app in the DMG;
7. Developer-ID sign, notarize, and staple the DMG;
8. regenerate SHA-256 after signing/stapling;
9. generate the Ed25519-signed Sparkle appcast;
10. publish the GitHub release.

The release keychain and App Store Connect API key file exist only in the runner's temporary directory and are removed at the end of the job.

## Local release verification

With a Developer ID identity and notarization API credentials available in the environment:

```bash
cd Chevron7
CHEVRON7_VERSION=0.13.0 SPARKLE_PUBLIC_ED_KEY="..." ./build_app.sh --release package
CODE_SIGN_IDENTITY="Developer ID Application: ..." bash scripts/sign-release.sh "$(swift build -c release --show-bin-path)/Chevron7.app"
APPLE_API_KEY_FILE=/path/AuthKey.p8 APPLE_API_KEY_ID=... APPLE_API_ISSUER_ID=... bash scripts/notarize-release.sh "$(swift build -c release --show-bin-path)/Chevron7.app"
```

Do not use `codesign --deep` for release signing. Sparkle's nested helper components require deliberate signing and preservation of the Downloader XPC service's entitlements.
