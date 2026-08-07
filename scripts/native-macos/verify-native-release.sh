#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
dmg_path="${repo_root}/build/native/Autogram-native-preview.dmg"
check_signature=false
check_notarization=false
mountpoint=""
mounted=false
mach_o_count=0

usage() {
    printf '%s\n' "Usage: $0 [--check-signature] [--check-notarization] [DMG_PATH]" >&2
    exit 64
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ "${mounted}" == true ]]; then
        hdiutil detach "${mountpoint}" -quiet || true
    fi
    if [[ -n "${mountpoint}" ]]; then
        rmdir "${mountpoint}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-signature)
            check_signature=true
            ;;
        --check-notarization)
            check_notarization=true
            ;;
        -h|--help)
            usage
            ;;
        -*)
            usage
            ;;
        *)
            [[ "${dmg_path}" == "${repo_root}/build/native/Autogram-native-preview.dmg" ]] || usage
            dmg_path="$1"
            ;;
    esac
    shift
done

command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is required to verify a DMG"
command -v file >/dev/null 2>&1 || fail "file is required to inspect Mach-O files"
command -v plutil >/dev/null 2>&1 || fail "plutil is required to validate plist files"
command -v python3 >/dev/null 2>&1 || fail "python3 is required to validate the capabilities response"
[[ -f "${dmg_path}" ]] || fail "DMG is missing: ${dmg_path}"

mountpoint="$(mktemp -d "${TMPDIR:-/tmp}/autogram-native-verify.XXXXXX")"
hdiutil attach -readonly -nobrowse -noverify -mountpoint "${mountpoint}" "${dmg_path}" >/dev/null
mounted=true

app_bundle="${mountpoint}/Autogram.app"
main_executable="${app_bundle}/Contents/MacOS/Autogram"
helper_executable="${app_bundle}/Contents/Helpers/AutogramCLI-arm64"
runtime_java="${app_bundle}/Contents/runtime/bin/java"

[[ -d "${app_bundle}" ]] || fail "DMG does not contain Autogram.app"
[[ -L "${mountpoint}/Applications" && "$(readlink "${mountpoint}/Applications")" == "/Applications" ]] || fail "DMG Applications link is missing"
[[ -f "${mountpoint}/README.md" ]] || fail "DMG README is missing"
[[ -x "${main_executable}" ]] || fail "Native app executable is missing"
[[ -x "${helper_executable}" ]] || fail "ARM64 helper is missing"
[[ -x "${runtime_java}" ]] || fail "Bundled runtime java is missing"

minimum_version="$(plutil -extract LSMinimumSystemVersion raw "${app_bundle}/Contents/Info.plist")"
minimum_major="${minimum_version%%.*}"
[[ "${minimum_major}" =~ ^[0-9]+$ && "${minimum_major}" -ge 27 ]] || fail "Bundle minimum macOS version must be 27 or later"

while IFS= read -r -d '' candidate; do
    file_description="$(file -b "${candidate}")"
    if [[ "${file_description}" == *Mach-O* ]]; then
        mach_o_count=$((mach_o_count + 1))
        [[ "${file_description}" == *arm64* ]] || fail "Non-ARM64 Mach-O file: ${candidate#"${mountpoint}/"}"
        [[ "${file_description}" != *x86_64* && "${file_description}" != *i386* ]] || fail "Intel Mach-O file: ${candidate#"${mountpoint}/"}"
    fi
done < <(find "${app_bundle}" -type f -print0)
[[ "${mach_o_count}" -gt 0 ]] || fail "No Mach-O files found in the app bundle"

while IFS= read -r -d '' candidate; do
    relative_path="${candidate#"${app_bundle}/"}"
    file_description="$(file -b "${candidate}")"
    if [[ "${file_description}" == *Mach-O* ]]; then
        case "${relative_path}" in
            Contents/MacOS/Autogram|Contents/Helpers/AutogramCLI-arm64|Contents/runtime/*)
                ;;
            *)
                fail "Unexpected executable code: ${relative_path}"
                ;;
        esac
    fi
done < <(find "${app_bundle}" -type f -print0)

[[ -z "$(find "${app_bundle}" \( -name '.git' -o -name '.hg' -o -name '.svn' -o -iname '*cache*' -o -iname '*.log' -o -iname '*.map' -o -iname '*.java' -o -iname '*.swift' -o -iname '*.c' -o -iname '*.h' -o -iname '*.m' -o -iname '*.mm' -o -iname '*.pem' -o -iname '*.key' -o -iname '*.p12' -o -iname '*.pfx' -o -iname '*.mobileprovision' -o -iname '*provisionprofile*' -o -iname '*x86_64*' -o -iname '*rosetta*' \) -print -quit)" ]] || fail "Forbidden source, map, log, cache, repository, private key, provisioning, Intel, or Rosetta artifact in bundle"
[[ -z "$(rg -a -l -e '/Users/' -e '/home/' -e '/private/var/folders/' "${app_bundle}" 2>/dev/null || true)" ]] || fail "Personal absolute path found in bundle"

workflow_root="${app_bundle}/Contents/Resources/Sign PDFs with Autogram.workflow/Contents"
plutil -lint "${workflow_root}/Info.plist" >/dev/null
plutil -lint "${workflow_root}/document.wflow" >/dev/null

capabilities_response="$(printf '%s' '{"protocolVersion":1,"requestId":"native-release-audit","operation":"CAPABILITIES","payload":{}}' | "${helper_executable}" --cli --machine-readable --protocol-version 1 --operation CAPABILITIES)"
CAPABILITIES_RESPONSE="${capabilities_response}" python3 - <<'PY'
import json
import os

events = [json.loads(line) for line in os.environ["CAPABILITIES_RESPONSE"].splitlines() if line.strip()]
completed = next((event for event in events if event.get("type") == "session.completed"), None)
if completed is None or completed.get("protocolVersion") != 1:
    raise SystemExit("CAPABILITIES did not return a protocol v1 completion event")
payload = completed.get("payload", {})
if "PAdES_BASELINE_T" not in payload.get("signatureLevels", []):
    raise SystemExit("CAPABILITIES does not require PAdES baseline T")
policy = payload.get("timestampPolicy", {})
if policy.get("required") is not True or policy.get("qualified") is not True:
    raise SystemExit("CAPABILITIES does not require qualified timestamps")
PY

if [[ "${check_signature}" == true ]]; then
    codesign --verify --deep --strict --verbose=2 "${app_bundle}"
fi
if [[ "${check_notarization}" == true ]]; then
    spctl --assess --type execute --verbose=4 "${app_bundle}"
fi

python3 - "${dmg_path}" "${minimum_version}" "${mach_o_count}" "${check_signature}" "${check_notarization}" <<'PY'
import json
import os
import sys

print(json.dumps({
    "dmg": os.path.abspath(sys.argv[1]),
    "status": "passed",
    "minimumMacOS": sys.argv[2],
    "machOFiles": int(sys.argv[3]),
    "capabilities": {"protocolVersion": 1, "qualifiedTimestampRequired": True},
    "signatureChecked": sys.argv[4] == "true",
    "notarizationChecked": sys.argv[5] == "true",
}, sort_keys=True))
PY
