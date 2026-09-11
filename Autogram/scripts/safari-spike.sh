#!/bin/bash
set -euo pipefail

# Answers the three unknowns behind the Safari extension in one run:
#   1. does Safari load a hand-assembled, adhoc-signed .appex
#   2. does the mach-lookup temporary exception hold without a Team ID
#   3. what is the ceiling on a native message
#
# Everything that can be checked without Safari is checked here. Enabling an
# unsigned extension is an in-memory Safari setting with no preference key, so
# that one step stays manual.

cd "$(dirname "$0")/.."

APP="/Applications/Autogram macOS.app"
APPEX="$APP/Contents/PlugIns/AutogramWebExtension.appex"
SERVICE="sk.autogram.Autogram.webbridge"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }

step "1. Je appex v nainštalovanej aplikácii?"
if [[ -d "$APPEX" ]]; then
    ok "$APPEX"
else
    bad "appex chýba - spusti najprv: DEVELOPER_DIR=\"/Applications/Xcode-beta.app/Contents/Developer\" ./build_app.sh --release install"
    exit 1
fi

step "2. Má appex vložený mach-lookup entitlement?"
if codesign -d --entitlements - "$APPEX" 2>/dev/null | grep -q "$SERVICE"; then
    ok "temporary-exception.mach-lookup.global-name obsahuje $SERVICE"
else
    bad "entitlement chýba - Safari appex načíta, ale spojenie s aplikáciou zlyhá"
fi

step "3. Sedí principal class a extension point?"
POINT=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$APPEX/Contents/Info.plist" 2>/dev/null || echo "")
CLASS=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPrincipalClass" "$APPEX/Contents/Info.plist" 2>/dev/null || echo "")
[[ "$POINT" == "com.apple.Safari.web-extension" ]] && ok "extension point: $POINT" || bad "extension point: '$POINT'"
[[ "$CLASS" == "AutogramWebExtensionHandler" ]] && ok "principal class: $CLASS" || bad "principal class: '$CLASS'"

step "4. Sú web časti rozšírenia v Resources?"
for file in manifest.json background.js content.js inject.js; do
    [[ -f "$APPEX/Contents/Resources/$file" ]] && ok "$file" || bad "$file chýba"
done

step "5. Je launchd agent zaregistrovaný?"
if launchctl print "gui/$(id -u)/sk.autogram.Autogram.webbridge" >/dev/null 2>&1; then
    ok "agent sk.autogram.Autogram.webbridge je v launchd"
else
    bad "agent chýba - spusti: ./scripts/install-webbridge-agent.sh"
fi

step "6. Beží aplikácia a je dosiahnuteľná cez agenta?"
if ! pgrep -x "Autogram" >/dev/null 2>&1; then
    echo "  Aplikácia nebeží, spúšťam ju..."
    open "$APP"
    sleep 4
fi
if "$(swift build --show-bin-path 2>/dev/null)/webbridge-probe" 2>&1 | sed 's/^/  /'; then
    ok "XPC transport funguje (appková polovica je overená)"
else
    bad "XPC spojenie zlyhalo - pozri log: log show --last 2m --predicate 'subsystem == \"sk.autogram.Autogram\"'"
fi

cat <<'MANUAL'

──────────────────────────────────────────────────────────────────────────
Zvyšok sa bez teba spraviť nedá. Tri kroky v Safari:

  1. Safari > Settings > Advanced > zapni "Show features for web developers"
     (IncludeDevelopMenu už máš zapnuté)

  2. Safari > Develop > Allow Unsigned Extensions
     Pozor: Safari to zabudne pri každom štarte, musíš to zapnúť znova.

  3. Safari > Settings > Extensions > zapni "Autogram macOS na štátnych weboch"

Potom otvor https://www.slovensko.sk/ a vo web inspectore konzoly spusti:

     await window.autogramMacOS.status()

  Očakávaný výsledok:  { ok: true, ready: false, version: "0.3.1" }
  (presne to už vracia sonda v kroku 6 bez Safari)

  ready:false je správne - transport funguje, len podpisový handler ešte
  nie je zapojený (to je ďalšia úloha, nie chyba).

  Ak dostaneš { ok:false, error:"Autogram macOS nebeží..." }, appex sa načítal,
  ale mach-lookup výnimka neprešla - to je presne tá neznáma, ktorú sonda meria,
  a znamená to prepnúť na záložný plán (interný HTTP server na 127.0.0.1
  s tokenom) popísaný v špecifikácii.
──────────────────────────────────────────────────────────────────────────
MANUAL
