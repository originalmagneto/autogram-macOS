# Autogram macOS App Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and install the native ARM64 application as `/Applications/Autogram macOS.app` with the approved signed-document icon.

**Architecture:** Keep the Xcode target and executable name `Autogram` so test-host paths remain stable. Set the user-facing display name in `Info.plist`, compile a standard macOS AppIcon asset, and make release scripts emit `Autogram macOS.app`. Installation copies only that verified native bundle into `/Applications`.

**Tech Stack:** SwiftUI, Xcode asset catalogs, SVG source artwork, ImageMagick, shell release scripts, macOS code signing.

## Global Constraints

- Display name and application bundle name: `Autogram macOS`.
- Bundle identifier remains `digital.slovensko.autogram.native`.
- The original Java Autogram installation is not modified or replaced.
- The icon contains no words or letters.
- The application, helper, and bundled Java runtime are ARM64.
- Minimum operating system remains macOS 27.0.

---

### Task 1: Product name and AppIcon

**Files:**
- Create: `native-macos/Autogram/Resources/AppIcon.svg`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`
- Create: `native-macos/Autogram/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`
- Modify: `native-macos/Autogram/Resources/Info.plist`
- Modify: `native-macos/Autogram.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: approved blue document, signature stroke, and gold qualified-seal composition.
- Produces: compiled `AppIcon` and `CFBundleDisplayName` value `Autogram macOS`.

- [ ] **Step 1: Add deterministic vector artwork**

Create a 1024 by 1024 SVG with a blue rounded-square background, white folded document, blue signing stroke, and gold checkmarked seal. Keep the composition free of text and letters.

- [ ] **Step 2: Render standard macOS icon sizes**

Run ImageMagick against `AppIcon.svg` for 16, 32, 64, 128, 256, 512, and 1024 pixel PNG outputs. Map those files to the ten standard macOS AppIcon slots in `Contents.json`.

- [ ] **Step 3: Connect the display name and asset**

Add `CFBundleDisplayName` with value `Autogram macOS` to `Info.plist`. Set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in both application build configurations without renaming the Xcode target or executable.

- [ ] **Step 4: Verify the Xcode product**

Run:

```bash
/usr/bin/env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project native-macos/Autogram.xcodeproj \
  -scheme Autogram \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`; the product plist reports `Autogram macOS` and compiled assets contain `AppIcon`.

- [ ] **Step 5: Commit**

```bash
git add native-macos/Autogram/Resources native-macos/Autogram.xcodeproj/project.pbxproj
git commit -m "feat(macos): add native app identity"
```

### Task 2: Release bundle and Applications installation

**Files:**
- Modify: `scripts/native-macos/build-native-app.sh`
- Modify: `scripts/native-macos/sign-native-app.sh`
- Modify: `scripts/native-macos/package-native-dmg.sh`
- Modify: `scripts/native-macos/verify-native-release.sh`

**Interfaces:**
- Consumes: Xcode product `Autogram.app` with display name and compiled AppIcon.
- Produces: verified `build/native/Autogram macOS.app` and installed `/Applications/Autogram macOS.app`.

- [ ] **Step 1: Rename only the release bundle**

Update release-script bundle paths from `Autogram.app` to `Autogram macOS.app`. Continue reading the temporary Xcode product from `Autogram.app` and copy it to the new release-bundle path.

- [ ] **Step 2: Build and sign the ARM64 bundle**

Run `scripts/native-macos/build-native-app.sh`, then ad hoc sign the complete bundle with the existing native entitlements. Verify the signature and confirm the app executable, helper, and runtime `java` executable are ARM64.

- [ ] **Step 3: Install without touching other Autogram applications**

If `/Applications/Autogram macOS.app` exists, replace only that exact bundle. Copy the verified build to `/Applications/Autogram macOS.app`. Do not remove or overwrite any other application bundle.

- [ ] **Step 4: Verify installed identity and launch**

Verify the installed bundle identifier, display name, icon resource, code signature, and ARM64 binaries. Open the already-signed PDF with `/Applications/Autogram macOS.app` and confirm I.CA SecureStore and existing signatures appear.

- [ ] **Step 5: Commit**

```bash
git add scripts/native-macos
git commit -m "build(macos): name native app bundle"
```
