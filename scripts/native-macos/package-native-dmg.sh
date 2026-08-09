#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
build_root="${repo_root}/build/native"
source_app="${build_root}/Autogram macOS.app"
readme_source="${repo_root}/native-macos/README.md"
output_dmg="${build_root}/Autogram-native-preview.dmg"
checksum_file="${output_dmg}.sha256"
volume_name="Autogram Native Preview"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/autogram-native-dmg.XXXXXX")"
temporary_dmg="$(mktemp "${TMPDIR:-/tmp}/autogram-native-preview.XXXXXX.dmg")"

cleanup() {
    rm -rf "${staging_dir}" "${temporary_dmg}"
}
trap cleanup EXIT

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ -d "${source_app}" ]] || fail "Native app bundle is missing: ${source_app}"
[[ -f "${readme_source}" ]] || fail "Native macOS README is missing: ${readme_source}"
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is required to create a DMG"
command -v shasum >/dev/null 2>&1 || fail "shasum is required to write the DMG checksum"

ditto "${source_app}" "${staging_dir}/Autogram macOS.app"
ln -s /Applications "${staging_dir}/Applications"
cp "${readme_source}" "${staging_dir}/README.md"

hdiutil create \
    -volname "${volume_name}" \
    -srcfolder "${staging_dir}" \
    -format UDZO \
    -ov \
    "${temporary_dmg}" >/dev/null

mkdir -p "${build_root}"
mv -f "${temporary_dmg}" "${output_dmg}"
shasum -a 256 "${output_dmg}" >"${checksum_file}"

printf 'Created %s\n' "${output_dmg}"
printf 'Wrote %s\n' "${checksum_file}"
