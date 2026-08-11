#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGNER="$SCRIPT_DIR/autogram-cli-sign.sh"

TMP_DIR="$(mktemp -d -t autogram-cli-sign-test)"
trap 'rm -rf "$TMP_DIR"' EXIT

HELPER="$TMP_DIR/helper"
REQUEST_LOG="$TMP_DIR/request.json"
SOURCE="$TMP_DIR/source.pdf"
TARGET="$TMP_DIR/target.pdf"

cat > "$HELPER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' '--machine-readable'
  exit 0
fi

request="$(cat)"
printf '%s\n' "$request" > "$REQUEST_LOG"
printf '%s\n' '{"protocolVersion":1,"type":"session.completed","sessionId":"test","payload":{}}'
SH
chmod +x "$HELPER"
printf '%%PDF-1.4\n%%%%EOF\n' > "$SOURCE"

printf '1234' | REQUEST_LOG="$REQUEST_LOG" AUTOGRAM_NATIVE_BIN="$HELPER" "$SIGNER" \
  --driver secure_store \
  --key certificate-1 \
  --pin-stdin \
  --pdf-level PAdES_BASELINE_T \
  --tsa-server https://tsa.example.test \
  --target "$TARGET" \
  "$SOURCE" >/dev/null

grep -q '"operation":"SIGN"' "$REQUEST_LOG"
grep -q '"certificateSerial":"certificate-1"' "$REQUEST_LOG"
grep -q '"source":"'"$SOURCE"'"' "$REQUEST_LOG"

current_line="$(grep -n '/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64' "$SIGNER" | head -1 | cut -d: -f1)"
legacy_line="$(grep -n '/Applications/Autogram NATIVE.app/Contents/Helpers/AutogramCLI-arm64' "$SIGNER" | head -1 | cut -d: -f1 || true)"
[[ -n "$current_line" ]]
[[ -z "$legacy_line" || "$current_line" -lt "$legacy_line" ]]

echo "CLI Quick Action helper selection and machine request passed."
