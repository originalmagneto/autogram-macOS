#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
app_bundle="${repo_root}/build/native/Autogram macOS.app"
main_executable="${app_bundle}/Contents/MacOS/Autogram"
runtime_java="${app_bundle}/Contents/runtime/bin/java"
java_entitlements="${repo_root}/native-macos/Helpers/JavaHelper.entitlements"
app_entitlements="${repo_root}/native-macos/Autogram/Resources/Autogram.entitlements"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || fail "DEVELOPER_ID_APPLICATION must be set before signing"
[[ -d "${app_bundle}" ]] || fail "Native app bundle is missing: ${app_bundle}"
[[ -x "${main_executable}" ]] || fail "Native app executable is missing: ${main_executable}"
[[ -x "${runtime_java}" ]] || fail "Bundled runtime java is missing: ${runtime_java}"
[[ -f "${java_entitlements}" ]] || fail "Java helper entitlements are missing: ${java_entitlements}"
[[ -f "${app_entitlements}" ]] || fail "Application entitlements are missing: ${app_entitlements}"
command -v codesign >/dev/null 2>&1 || fail "codesign is required to sign the native app"
command -v file >/dev/null 2>&1 || fail "file is required to inspect Mach-O files"

sign_code() {
    local target="$1"
    shift
    codesign --force --sign "${DEVELOPER_ID_APPLICATION}" --options runtime --timestamp "$@" "${target}"
}

while IFS= read -r -d '' candidate; do
    [[ "${candidate}" == "${main_executable}" || "${candidate}" == "${runtime_java}" ]] && continue
    if file -b "${candidate}" | rg -q 'Mach-O'; then
        sign_code "${candidate}"
    fi
done < <(find "${app_bundle}" -type f -print0)

sign_code "${runtime_java}" --entitlements "${java_entitlements}"
sign_code "${main_executable}"
sign_code "${app_bundle}" --entitlements "${app_entitlements}"

codesign --verify --deep --strict --verbose=2 "${app_bundle}"

main_library_validation="$(codesign -d --entitlements :- "${app_bundle}" 2>/dev/null | plutil -extract com.apple.security.cs.disable-library-validation raw -o - - 2>/dev/null || true)"
[[ -z "${main_library_validation}" ]] || fail "Main app must not disable library validation"

java_library_validation="$(codesign -d --entitlements :- "${runtime_java}" 2>/dev/null | plutil -extract com.apple.security.cs.disable-library-validation raw -o - - 2>/dev/null || true)"
[[ "${java_library_validation}" == "true" ]] || fail "Runtime java must disable library validation"

printf 'Signed and verified %s\n' "${app_bundle}"
