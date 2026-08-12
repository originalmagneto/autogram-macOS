#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
dmg_path="${repo_root}/build/native/Autogram-native-preview.dmg"
check_signature=false
check_notarization=false
mountpoint=""
mounted=false
attached_with_diskutil=false
mach_o_count=0

stage() {
    printf 'Verifying: %s\n' "$1"
}

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
        if [[ "${attached_with_diskutil}" == true ]]; then
            diskutil unmount "${mountpoint}" >/dev/null 2>&1 || true
        else
            hdiutil detach "${mountpoint}" -quiet || true
        fi
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

command -v file >/dev/null 2>&1 || fail "file is required to inspect Mach-O files"
command -v plutil >/dev/null 2>&1 || fail "plutil is required to validate plist files"
command -v python3 >/dev/null 2>&1 || fail "python3 is required to write the verification report"
[[ -f "${dmg_path}" ]] || fail "DMG is missing: ${dmg_path}"

mountpoint="$(mktemp -d "${TMPDIR:-/tmp}/autogram-native-verify.XXXXXX")"
stage "mounting DMG"
if command -v diskutil >/dev/null 2>&1 && diskutil image attach --help >/dev/null 2>&1; then
    diskutil image attach --readOnly --nobrowse --mountPoint "${mountpoint}" "${dmg_path}" >/dev/null
    attached_with_diskutil=true
else
    command -v hdiutil >/dev/null 2>&1 || fail "diskutil image attach or hdiutil is required to verify a DMG"
    hdiutil attach -readonly -nobrowse -noverify -mountpoint "${mountpoint}" "${dmg_path}" >/dev/null
fi
mounted=true

app_bundle="${mountpoint}/Autogram macOS.app"
main_executable="${app_bundle}/Contents/MacOS/Autogram"
helper_executable="${app_bundle}/Contents/Helpers/AutogramCLI-arm64"
quick_action_runner="${app_bundle}/Contents/Helpers/AutogramQuickActionRunner-arm64"
runtime_java="${app_bundle}/Contents/runtime/bin/java"

[[ -d "${app_bundle}" ]] || fail "DMG does not contain Autogram macOS.app"
[[ -L "${mountpoint}/Applications" && "$(readlink "${mountpoint}/Applications")" == "/Applications" ]] || fail "DMG Applications link is missing"
[[ -f "${mountpoint}/README.md" ]] || fail "DMG README is missing"
[[ -x "${main_executable}" ]] || fail "Native app executable is missing"
[[ -x "${helper_executable}" ]] || fail "ARM64 helper is missing"
[[ -x "${quick_action_runner}" ]] || fail "ARM64 Quick Action runner is missing"
[[ -x "${runtime_java}" ]] || fail "Bundled runtime java is missing"

stage "bundle metadata"
minimum_version="$(plutil -extract LSMinimumSystemVersion raw "${app_bundle}/Contents/Info.plist")"
minimum_major="${minimum_version%%.*}"
[[ "${minimum_major}" =~ ^[0-9]+$ && "${minimum_major}" -ge 27 ]] || fail "Bundle minimum macOS version must be 27 or later"

stage "ARM64 executable inventory"
while IFS= read -r -d '' candidate; do
    file_description="$(file -b "${candidate}")"
    if [[ "${file_description}" == *Mach-O* ]]; then
        mach_o_count=$((mach_o_count + 1))
        [[ "${file_description}" == *arm64* ]] || fail "Non-ARM64 Mach-O file: ${candidate#"${mountpoint}/"}"
        [[ "${file_description}" != *x86_64* && "${file_description}" != *i386* ]] || fail "Intel Mach-O file: ${candidate#"${mountpoint}/"}"
        relative_path="${candidate#"${app_bundle}/"}"
        case "${relative_path}" in
            Contents/MacOS/Autogram|Contents/Helpers/AutogramCLI-arm64|Contents/Helpers/AutogramQuickActionRunner-arm64|Contents/runtime/*)
                ;;
            *)
                fail "Unexpected executable code: ${relative_path}"
                ;;
        esac
    fi
done < <(find "${app_bundle}" -type f -print0)
[[ "${mach_o_count}" -gt 0 ]] || fail "No Mach-O files found in the app bundle"

stage "private and forbidden artifacts"
[[ -z "$(find "${app_bundle}" \( -name '.git' -o -name '.hg' -o -name '.svn' -o -iname '*cache*' -o -iname '*.log' -o -iname '*.map' -o -iname '*.java' -o -iname '*.swift' -o -iname '*.c' -o -iname '*.h' -o -iname '*.m' -o -iname '*.mm' -o -iname '*.pem' -o -iname '*.key' -o -iname '*.p12' -o -iname '*.pfx' -o -iname '*.mobileprovision' -o -iname '*provisionprofile*' -o -iname '*x86_64*' -o -iname '*rosetta*' \) -print -quit)" ]] || fail "Forbidden source, map, log, cache, repository, private key, provisioning, Intel, or Rosetta artifact in bundle"
for audit_path in \
    "${app_bundle}/Contents/Info.plist" \
    "${app_bundle}/Contents/MacOS" \
    "${app_bundle}/Contents/Helpers" \
    "${app_bundle}/Contents/Resources"; do
    "${script_dir}/assert-no-byte-patterns.py" "${audit_path}" '/Users/' '/home/' '/private/var/folders/' || fail "Personal absolute path found in first-party app files"
done

managed_workflow="${app_bundle}/Contents/Resources/Sign PDFs Autogram.workflow/Contents"
stage "Finder Quick Action"
[[ "$(cat "${managed_workflow}/Resources/managed-version")" == "3" ]] || fail "Managed workflow version is invalid"
plutil -lint "${managed_workflow}/Info.plist" >/dev/null
plutil -lint "${managed_workflow}/document.wflow" >/dev/null
[[ "$(plutil -extract workflowMetaData.workflowTypeIdentifier raw -o - "${managed_workflow}/document.wflow")" == "com.apple.Automator.servicesMenu" ]] || fail "Managed workflow is not a Finder Quick Action"
[[ "$(plutil -extract workflowMetaData.serviceApplicationBundleID raw -o - "${managed_workflow}/document.wflow")" == "com.apple.finder" ]] || fail "Managed workflow is not scoped to Finder"
[[ "$(plutil -extract workflowMetaData.serviceInputTypeIdentifier raw -o - "${managed_workflow}/document.wflow")" == "com.apple.Automator.fileSystemObject.PDF" ]] || fail "Managed workflow is not scoped to PDF files"
[[ -x "${managed_workflow}/Resources/autogram-quick-action.sh" ]] || fail "Managed workflow launcher is not executable"
[[ -x "${managed_workflow}/Resources/autogram-cli-sign.sh" ]] || fail "Managed workflow CLI signer is not executable"
bash -n "${managed_workflow}/Resources/autogram-quick-action.sh"
bash -n "${managed_workflow}/Resources/autogram-cli-sign.sh"
"${script_dir}/assert-no-byte-patterns.py" "${managed_workflow}" '/Users/' 'Intel' 'Rosetta' || fail "Managed workflow contains a personal path, Intel, or Rosetta text"
"${script_dir}/assert-no-byte-patterns.py" "${managed_workflow}" 'AUTOGRAM_NATIVE_BIN' 'AUTOGRAM_JSON_PYTHON' 'build/native' 'python3' || fail "Managed workflow contains a development override, build fallback, or Python dependency"

if [[ "${check_signature}" == true ]]; then
    stage "code signature"
    codesign --verify --deep --strict --verbose=2 "${app_bundle}"
fi
if [[ "${check_notarization}" == true ]]; then
    stage "notarization"
    spctl --assess --type execute --verbose=4 "${app_bundle}"
fi

stage "verification report"
python3 - "${dmg_path}" "${minimum_version}" "${mach_o_count}" "${check_signature}" "${check_notarization}" <<'PY'
import json
import os
import sys

print(json.dumps({
    "dmg": os.path.basename(sys.argv[1]),
    "status": "passed",
    "minimumMacOS": sys.argv[2],
    "machOFiles": int(sys.argv[3]),
    "capabilities": {"protocolVersion": 1, "qualifiedTimestampRequired": True},
    "signatureChecked": sys.argv[4] == "true",
    "notarizationChecked": sys.argv[5] == "true",
}, sort_keys=True))
PY
