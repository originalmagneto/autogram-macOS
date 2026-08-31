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

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.5.app/Contents/Developer}"
export MACOSX_DEPLOYMENT_TARGET="27.0"

echo "▸ swift build -c $MODE"
swift build -c "$MODE"

BIN_DIR=".build/arm64-apple-macosx/$MODE"
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

LEGACY_CONTENTS="${AUTOGRAM_LEGACY_APP_ROOT:-}"
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
else
    echo "Warning: Legacy Autogram CLI payload not found. CLI Quick Action will require an external legacy installation." >&2
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
    <string>0.2.2</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.2</string>
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

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✔ Hotovo: $APP_DIR"
echo "  Spustenie: open \"$APP_DIR\""

if [[ "$INSTALL" == true ]]; then
    INSTALL_DIR="/Applications/Autogram macOS.app"
    rm -rf "$INSTALL_DIR"
    ditto --rsrc --extattr --acl "$APP_DIR" "$INSTALL_DIR"
    echo "✔ Nainštalované: $INSTALL_DIR"
fi
