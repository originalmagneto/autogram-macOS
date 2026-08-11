#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIGNER="$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-cli-sign.sh"
WORKFLOW="$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow"

TMP_DIR="$(mktemp -d -t autogram-cli-sign-test)"
trap 'rm -rf "$TMP_DIR"' EXIT

HELPER="$TMP_DIR/helper"
REQUEST_LOG="$TMP_DIR/request.json"
SOURCE="$TMP_DIR/source.pdf"
TARGET="$TMP_DIR/target.pdf"
HELPER_X86="$TMP_DIR/helper-x86"

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

workflow_input_method="$(plutil -extract 'actions.0.action.ActionParameters.inputMethod' raw "$WORKFLOW")"
[[ "$workflow_input_method" == "1" ]] || {
  echo "Finder workflow must pass input as arguments (inputMethod=1)." >&2
  exit 1
}

lipo -thin x86_64 /usr/bin/python3 -output "$HELPER_X86"
set +e
printf '1234' | AUTOGRAM_NATIVE_BIN="$HELPER_X86" "$SIGNER" \
  --driver secure_store \
  --key certificate-1 \
  --pin-stdin \
  --pdf-level PAdES_BASELINE_T \
  --tsa-server https://tsa.example.test \
  --target "$TARGET" \
  "$SOURCE" >"$TMP_DIR/x86.out" 2>"$TMP_DIR/x86.err"
x86_status=$?
set -e
[[ "$x86_status" -eq 69 ]]
grep -q 'must contain an arm64 slice' "$TMP_DIR/x86.err"

set +e
printf '1234' | AUTOGRAM_NATIVE_BIN="$HELPER" AUTOGRAM_JSON_PYTHON="$HELPER_X86" "$SIGNER" \
  --driver secure_store \
  --key certificate-1 \
  --pin-stdin \
  --pdf-level PAdES_BASELINE_T \
  --tsa-server https://tsa.example.test \
  --target "$TARGET" \
  "$SOURCE" >"$TMP_DIR/python-x86.out" 2>"$TMP_DIR/python-x86.err"
python_x86_status=$?
set -e
[[ "$python_x86_status" -eq 69 ]]
grep -q 'Python 3 must contain an arm64 slice' "$TMP_DIR/python-x86.err"
rg -F '/usr/bin/arch -arm64 "$python_bin" -c' "$SIGNER" >/dev/null

current_line="$(grep -n '/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64' "$SIGNER" | head -1 | cut -d: -f1)"
legacy_line="$(grep -n '/Applications/Autogram NATIVE.app/Contents/Helpers/AutogramCLI-arm64' "$SIGNER" | head -1 | cut -d: -f1 || true)"
[[ -n "$current_line" ]]
[[ -z "$legacy_line" || "$current_line" -lt "$legacy_line" ]]

echo "CLI Quick Action helper selection and machine request passed."
