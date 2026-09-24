#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Marián Čuprík
# SPDX-License-Identifier: EUPL-1.2
set -euo pipefail

version="${1:?Usage: $0 VERSION DIST_DIR}"
dist="${2:?Usage: $0 VERSION DIST_DIR}"
: "${SPARKLE_PRIVATE_ED_KEY:?SPARKLE_PRIVATE_ED_KEY is required}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_root="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$package_root/.." && pwd)"
dmg="$dist/Chevron7-v$version.dmg"
[[ -f "$dmg" ]] || { echo "Missing update archive: $dmg" >&2; exit 1; }

generate_appcast="$(find "$package_root/.build" -type f -name generate_appcast -perm -111 -print -quit 2>/dev/null || true)"
[[ -n "$generate_appcast" ]] || {
    echo "Sparkle generate_appcast tool not found under $package_root/.build" >&2
    exit 1
}

updates="$(mktemp -d "${TMPDIR:-/tmp}/chevron7-appcast.XXXXXX")"
trap 'rm -rf "$updates"' EXIT
cp "$dmg" "$updates/"
"$script_dir/release-notes.sh" "$version" > "$updates/Chevron7-v$version.md"

download_prefix="https://github.com/originalmagneto/chevron7/releases/download/native-v$version/"
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "$download_prefix" \
    -o "$dist/appcast.xml" \
    "$updates"

grep -q 'sparkle:edSignature=' "$dist/appcast.xml" || {
    echo "Generated appcast has no Ed25519 signature" >&2
    exit 1
}
grep -q "Chevron7-v$version.dmg" "$dist/appcast.xml" || {
    echo "Generated appcast does not reference the release DMG" >&2
    exit 1
}

echo "✔ Sparkle appcast: $dist/appcast.xml"
