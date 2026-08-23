#!/bin/bash
set -euo pipefail

# Autogram.app build script — assembly of release binary into a macOS app bundle.
#
# Usage:
#   ./build_app.sh              # debug build (fast)
#   ./build_app.sh --release    # release build

MODE="debug"
if [[ "${1:-}" == "--release" ]]; then MODE="release"; fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.5.app/Contents/Developer}"

echo "▸ swift build -c $MODE"
swift build -c "$MODE"

BIN_DIR=".build/arm64-apple-macosx/$MODE"
APP_DIR="$BIN_DIR/Autogram.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/Autogram" "$CONTENTS/MacOS/Autogram"
cp "Assets/Autogram.icns" "$CONTENTS/Resources/Autogram.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>Autogram</string>
    <key>CFBundleName</key>
    <string>Autogram</string>
    <key>CFBundleDisplayName</key>
    <string>Autogram</string>
    <key>CFBundleIdentifier</key>
    <string>sk.autogram.Autogram</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Autogram</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
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

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✔ Hotovo: $APP_DIR"
echo "  Spustenie: open \"$APP_DIR\""
