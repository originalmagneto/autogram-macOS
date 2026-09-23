#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Marián Čuprík
# SPDX-License-Identifier: EUPL-1.2
# Read-only diagnostics for the OpenSC driver work (docs/OPENSC-INTEGRATION.md).
# Never logs in and never sends a PIN or BOK: it only lists readers, the card's
# ATR and driver, PKCS#11 slots and public objects, PIN objects with their
# remaining tries, the CryptoTokenKit view and what the Chevron7 engine detects.
#
# Usage: opensc-check.sh [--engine <AutogramCLI-arm64>]
# Tip:   opensc-check.sh 2>&1 | tee opensc-check.log

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
engine="${script_dir}/../.build/engine/Contents/Helpers/AutogramCLI-arm64"
if [[ "${1:-}" == "--engine" && -n "${2:-}" ]]; then
    engine="$2"
fi

section() { printf '\n=== %s ===\n' "$1"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1; printf '(exit %s)\n' "$?"; }

module=""
for candidate in /Library/OpenSC/lib/opensc-pkcs11.so /opt/homebrew/lib/opensc-pkcs11.so /usr/local/lib/opensc-pkcs11.so; do
    if [[ -f "$candidate" ]]; then module="$candidate"; break; fi
done
tools=""
for candidate in /Library/OpenSC/bin /opt/homebrew/bin /usr/local/bin; do
    if [[ -x "$candidate/pkcs11-tool" ]]; then tools="$candidate"; break; fi
done

section "Environment"
sw_vers
uname -m
printf 'OpenSC module: %s\n' "${module:-not found}"
printf 'OpenSC tools:  %s\n' "${tools:-not found}"
[[ -d /Applications/eID_klient.app ]] && echo "eID klient: installed" || echo "eID klient: not installed"
pgrep -lf "eID_klient" >/dev/null 2>&1 && echo "eID klient: running" || echo "eID klient: not running"
[[ -n "$module" ]] && { file "$module"; codesign -dv "$module" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3; }

if [[ -z "$module" || -z "$tools" ]]; then
    echo
    echo "OpenSC is not installed. Install OpenSC-<version>.dmg from https://github.com/OpenSC/OpenSC/releases and run this again."
    exit 1
fi

section "OpenSC version and card drivers"
run "$tools/opensc-tool" --info
run "$tools/opensc-tool" --list-drivers

section "Readers, ATR and matched driver"
run "$tools/opensc-tool" --list-readers
run "$tools/opensc-tool" --atr
run "$tools/opensc-tool" --name

section "PKCS#11 slots (no login)"
run "$tools/pkcs11-tool" --module "$module" --list-slots
slots="$("$tools/pkcs11-tool" --module "$module" --list-token-slots 2>/dev/null | sed -nE 's/^Slot [0-9]+ \((0x[0-9a-fA-F]+)\).*/\1/p')"
for slot in $slots; do
    section "Public objects in slot $slot (no login)"
    run "$tools/pkcs11-tool" --module "$module" --slot "$slot" --list-objects
    run "$tools/pkcs11-tool" --module "$module" --slot "$slot" --list-mechanisms
done

section "PKCS#15 view: certificates, keys, PINs and tries left (no login)"
run "$tools/pkcs15-tool" --list-certificates
run "$tools/pkcs15-tool" --list-keys
run "$tools/pkcs15-tool" --list-pins

section "CryptoTokenKit (native macOS view)"
run pluginkit -m -p com.apple.ctk-tokens
system_profiler SPSmartCardsDataType 2>/dev/null | sed -n '1,80p'

section "Chevron7 engine: DRIVERS (no PIN)"
if [[ -x "$engine" ]]; then
    printf '{"protocolVersion":1,"requestId":"opensc-check","operation":"DRIVERS","payload":{}}\n' \
        | "$engine" --cli --machine-readable --protocol-version 1 --operation DRIVERS 2>/dev/null \
        | grep '"driver.detected"' || echo "(no driver.detected event)"
    echo "An 'opensc' entry needs an engine built from this branch (scripts/build-engine.sh)."
else
    echo "Engine not found at $engine; run scripts/build-engine.sh or pass --engine."
fi
