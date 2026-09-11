#!/bin/bash
set -euo pipefail

# Autogram.app build script - assembly of a macOS app bundle.
#
# Usage:
#   ./build_app.sh                    # debug build (fast)
#   ./build_app.sh --release          # release build
#   ./build_app.sh install            # debug build and install into /Applications
#   ./build_app.sh --release install  # release build and install into /Applications

MODE="debug"
INSTALL=false
for argument in "$@"; do
    case "$argument" in
        --release) MODE="release" ;;
        install) INSTALL=true ;;
        *)
            echo "Usage: $0 [--release] [install]" >&2
            exit 2
            ;;
    esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export MACOSX_DEPLOYMENT_TARGET="27.0"

echo "▸ swift build -c $MODE"
swift build -c "$MODE"

# Ask SwiftPM where it put the products: Xcode 27 toolchains use .build/out/Products/<Mode>,
# older ones .build/arm64-apple-macosx/<mode>.
BIN_DIR="$(swift build -c "$MODE" --show-bin-path)"
APP_DIR="$BIN_DIR/Autogram.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/Autogram" "$CONTENTS/MacOS/Autogram"
if [[ -x "$BIN_DIR/pkcs11-helper" ]]; then
    cp "$BIN_DIR/pkcs11-helper" "$CONTENTS/MacOS/pkcs11-helper"
fi
cp "Assets/Autogram.icns" "$CONTENTS/Resources/Autogram.icns"
ditto "Assets/Autogram Finder Quick Action.workflow" "$CONTENTS/Resources/Autogram Finder Quick Action.workflow"

# Preferred source of the signing engine: the in-repo Java fork built by
# scripts/build-engine.sh. A legacy app bundle is only a fallback.
LEGACY_CONTENTS="${AUTOGRAM_LEGACY_APP_ROOT:-}"
ENGINE_BUILD=".build/engine/Contents"
if [[ -z "$LEGACY_CONTENTS" && -x "$ENGINE_BUILD/Helpers/AutogramCLI-arm64" && -f "$ENGINE_BUILD/app/autogram.jar" ]]; then
    LEGACY_CONTENTS="$ENGINE_BUILD"
fi
if [[ -z "$LEGACY_CONTENTS" ]]; then
    for candidate in /Applications/*.app/Contents "$HOME"/Applications/*.app/Contents; do
        if [[ -x "$candidate/Helpers/AutogramCLI-arm64" \
              && -x "$candidate/Helpers/AutogramQuickActionRunner-arm64" \
              && -f "$candidate/app/autogram.jar" \
              && -d "$candidate/app/dependency-jars" \
              && -d "$candidate/runtime" ]]; then
            LEGACY_CONTENTS="$candidate"
            break
        fi
    done
fi

if [[ -n "$LEGACY_CONTENTS" \
      && -x "$LEGACY_CONTENTS/Helpers/AutogramCLI-arm64" \
      && -x "$LEGACY_CONTENTS/Helpers/AutogramQuickActionRunner-arm64" \
      && -f "$LEGACY_CONTENTS/app/autogram.jar" \
      && -d "$LEGACY_CONTENTS/app/dependency-jars" \
      && -d "$LEGACY_CONTENTS/runtime" ]]; then
    mkdir -p "$CONTENTS/Helpers" "$CONTENTS/app"
    ditto "$LEGACY_CONTENTS/Helpers" "$CONTENTS/Helpers"
    cp "$LEGACY_CONTENTS/app/autogram.jar" "$CONTENTS/app/autogram.jar"
    ditto "$LEGACY_CONTENTS/app/dependency-jars" "$CONTENTS/app/dependency-jars"
    ditto "$LEGACY_CONTENTS/runtime" "$CONTENTS/runtime"

    MACHINE_SETTINGS_PATCH_ROOT="Assets/LegacyEnginePatches"
    MACHINE_SETTINGS_PATCH="digital/slovensko/autogram/ui/machine/MachineSettings.class"
    if [[ ! -f "$MACHINE_SETTINGS_PATCH_ROOT/$MACHINE_SETTINGS_PATCH" ]] || ! command -v jar >/dev/null 2>&1; then
        echo "Error: Java machine settings patch or jar tool is unavailable." >&2
        exit 1
    fi
    jar uf "$CONTENTS/app/autogram.jar" -C "$MACHINE_SETTINGS_PATCH_ROOT" "$MACHINE_SETTINGS_PATCH"
else
    echo "Warning: signing engine not found. Run scripts/build-engine.sh first; without it KEP signing falls back to Keychain/DEMO and the Finder Quick Action cannot sign." >&2
fi
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>org.autogram.asice</string>
            <key>UTTypeDescription</key>
            <string>ASiC-E signed container</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.zip-archive</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>asice</string>
                </array>
                <key>public.mime-type</key>
                <string>application/vnd.etsi.asic-e+zip</string>
            </dict>
        </dict>
    </array>
    <key>CFBundleIconFile</key>
    <string>Autogram</string>
    <key>CFBundleName</key>
    <string>Autogram</string>
    <key>CFBundleDisplayName</key>
    <string>Autogram</string>
    <key>CFBundleIdentifier</key>
    <string>sk.autogram.Autogram</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>sk.autogram.Autogram.ezzk</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>autogram</string>
            </array>
        </dict>
    </array>
    <key>CFBundleVersion</key>
    <string>0.3.1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Autogram</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
                <string>org.autogram.asice</string>
            </array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Autogram Signing Bridge</string>
            </dict>
            <key>NSMessage</key>
            <string>signFiles</string>
            <key>NSPortName</key>
            <string>Autogram</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>com.adobe.pdf</string>
                <string>org.autogram.asice</string>
            </array>
            <key>NSRequiredContext</key>
            <dict>
                <key>NSApplicationIdentifier</key>
                <string>com.apple.finder</string>
            </dict>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
        <key>NSExceptionDomains</key>
        <dict>
            <key>tsa.disig.sk</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>timestamp.sectigo.com</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>tsa.belgium.be</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
        </dict>
    </dict>
    <key>NSHumanReadableCopyright</key>
    <string>Zaručená konverzia podľa § 35–39 zákona č. 305/2013 Z. z.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

cat > "$CONTENTS/PkgInfo" <<'PKG'
APPL????
PKG

# ---------------------------------------------------------------------------
# Safari web extension: a hand-assembled .appex, because this project builds
# with SwiftPM and has no Xcode target to produce one.
#
# The extension is sandboxed by Safari and only relays native messages to the
# app over a Mach service, which the temporary-exception entitlement lets it
# look up. That exception needs neither a Team ID nor an app group, so it also
# holds under the adhoc signature used here. Distribution still needs a
# Developer ID and notarization; unsigned, Safari loads it only while
# "Allow Unsigned Extensions" is on in the Develop menu.
# ---------------------------------------------------------------------------
# launchd agent that owns the Mach service name. A GUI app cannot publish one:
# launchd hands the receive right only to the process it launches for the name.
# The agent is a rendezvous point, no document ever passes through it.
AGENT_BIN="$BIN_DIR/autogram-webbridge-agent"
if [[ -x "$AGENT_BIN" ]]; then
    cp "$AGENT_BIN" "$CONTENTS/Helpers/autogram-webbridge-agent" 2>/dev/null \
        || { mkdir -p "$CONTENTS/Helpers" && cp "$AGENT_BIN" "$CONTENTS/Helpers/autogram-webbridge-agent"; }
fi

EXTENSION_BIN="$BIN_DIR/AutogramWebExtensionHandler"
if [[ -x "$EXTENSION_BIN" ]]; then
    APPEX="$CONTENTS/PlugIns/AutogramWebExtension.appex"
    rm -rf "$APPEX"
    mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
    cp "$EXTENSION_BIN" "$APPEX/Contents/MacOS/AutogramWebExtension"

    if [[ -d "WebExtension/dist" ]]; then
        ditto "WebExtension/dist" "$APPEX/Contents/Resources"
    else
        echo "  (upozornenie: WebExtension/dist chýba, rozšírenie bude bez web častí)"
    fi

    cat > "$APPEX/Contents/Info.plist" <<'APPEXPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Autogram na štátnych weboch</string>
    <key>CFBundleDisplayName</key>
    <string>Autogram na štátnych weboch</string>
    <key>CFBundleIdentifier</key>
    <string>sk.autogram.Autogram.WebExtension</string>
    <key>CFBundleExecutable</key>
    <string>AutogramWebExtension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.Safari.web-extension</string>
        <key>NSExtensionPrincipalClass</key>
        <string>AutogramWebExtensionHandler</string>
    </dict>
</dict>
APPEXPLIST
    echo '</plist>' >> "$APPEX/Contents/Info.plist"

    APPEX_ENTITLEMENTS="$(mktemp -t autogram-appex-entitlements).plist"
    cat > "$APPEX_ENTITLEMENTS" <<'ENTPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>sk.autogram.Autogram.webbridge</string>
    </array>
</dict>
</plist>
ENTPLIST

    codesign --force --sign - --entitlements "$APPEX_ENTITLEMENTS" "$APPEX" >/dev/null 2>&1 \
        || echo "  (upozornenie: appex sa nepodarilo podpísať)"
    rm -f "$APPEX_ENTITLEMENTS"
    echo "▸ Safari rozšírenie: $APPEX"
fi

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✔ Hotovo: $APP_DIR"
echo "  Spustenie: open \"$APP_DIR\""

if [[ "$INSTALL" == true ]]; then
    INSTALL_DIR="/Applications/Autogram macOS.app"
    rm -rf "$INSTALL_DIR"
    ditto --rsrc --extattr --acl "$APP_DIR" "$INSTALL_DIR"
    echo "✔ Nainštalované: $INSTALL_DIR"
fi
