#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
dmg_path="${repo_root}/build/native/Autogram-native-preview.dmg"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ -n "${NOTARYTOOL_PROFILE:-}" ]] || fail "NOTARYTOOL_PROFILE must be set before notarization"

if [[ $# -gt 1 ]]; then
    fail "Usage: $0 [DMG_PATH]"
fi
if [[ $# -eq 1 ]]; then
    dmg_path="$1"
fi

[[ -f "${dmg_path}" ]] || fail "DMG is missing: ${dmg_path}"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required for notarization"
command -v spctl >/dev/null 2>&1 || fail "spctl is required for notarization verification"

xcrun notarytool submit "${dmg_path}" --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
xcrun stapler staple "${dmg_path}"
xcrun stapler validate "${dmg_path}"
spctl --assess --type open --context context:primary-signature --verbose=4 "${dmg_path}"

printf 'Notarized and stapled %s\n' "${dmg_path}"
