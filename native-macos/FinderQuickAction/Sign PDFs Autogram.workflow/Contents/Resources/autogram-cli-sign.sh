#!/usr/bin/env bash
set -euo pipefail

has_arm64_slice() {
  /usr/bin/file -Lb "$1" | /usr/bin/grep -q 'arm64'
}

resolve_runner() {
  local helper runner

  for helper in \
    "/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64" \
    "$HOME/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64"; do
    runner="$(dirname "$helper")/AutogramQuickActionRunner-arm64"
    if [[ -x "$helper" && -x "$runner" ]] && has_arm64_slice "$helper" && has_arm64_slice "$runner"; then
      printf '%s\n' "$runner"
      return 0
    fi
  done
  return 1
}

absolute_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd)" "$(basename "$path")"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  autogram-cli-sign.sh [options] <PDF>

Required for signing:
  --driver NAME --key SERIAL --pin-stdin --target PATH --tsa-server URL

Other options:
  --list-keys --pdf-level LEVEL

Autogram macOS and an arm64-capable PKCS#11 driver are required.
EOF
}

driver=""
certificate=""
target=""
level="PAdES_BASELINE_T"
tsa=""
pin_stdin=0
list_keys=0
declare -a sources=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver) driver="${2:-}"; shift 2 ;;
    --key) certificate="${2:-}"; shift 2 ;;
    --target) target="${2:-}"; shift 2 ;;
    --pdf-level) level="${2:-}"; shift 2 ;;
    --tsa-server) tsa="${2:-}"; shift 2 ;;
    --pin-stdin) pin_stdin=1; shift ;;
    --list-keys) list_keys=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unsupported option: $1" >&2; usage >&2; exit 64 ;;
    *) sources+=("$1"); shift ;;
  esac
done

runner="$(resolve_runner || true)"
[[ -n "$runner" ]] || { echo "Autogram macOS ARM64 helper was not found." >&2; exit 69; }
[[ "$pin_stdin" -eq 1 ]] || { echo "--pin-stdin is required." >&2; exit 64; }
[[ -n "$driver" ]] || { echo "--driver is required." >&2; exit 64; }

if [[ "$list_keys" -eq 1 ]]; then
  exec "$runner" --operation CERTIFICATES --driver "$driver" --pin-stdin
fi

[[ ${#sources[@]} -eq 1 ]] || { echo "Exactly one PDF source is required." >&2; exit 64; }
[[ -n "$certificate" ]] || { echo "--key is required." >&2; exit 64; }
[[ -n "$target" ]] || { echo "--target is required." >&2; exit 64; }
[[ -n "$tsa" ]] || { echo "--tsa-server is required." >&2; exit 64; }

echo "Signing: ${sources[0]}"
exec "$runner" \
  --operation SIGN \
  --driver "$driver" \
  --certificate "$certificate" \
  --pin-stdin \
  --signature-level "$level" \
  --tsa-server "$tsa" \
  --target "$(absolute_path "$target")" \
  --source "$(absolute_path "${sources[0]}")"
