#!/bin/bash
set -euo pipefail

# Registers the launchd agent that owns the web bridge Mach service.
# Needed because launchd, not the app, decides who may publish a service name.

APP="${1:-/Applications/Autogram macOS.app}"
LABEL="sk.autogram.Autogram.webbridge"
AGENT="$APP/Contents/Helpers/autogram-webbridge-agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[[ -x "$AGENT" ]] || { echo "Agent chýba: $AGENT" >&2; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$AGENT</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>$LABEL</key>
        <true/>
    </dict>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "✔ Agent zaregistrovaný: $LABEL"
launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | sed -n '1,6p' || true
