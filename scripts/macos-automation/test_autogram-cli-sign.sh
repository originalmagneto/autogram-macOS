#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIGNER="$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-cli-sign.sh"
WORKFLOW="$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow"
RUNNER_SOURCE="$REPO_ROOT/scripts/native-macos/autogram-quick-action-runner.swift"

TMP_DIR="$(mktemp -d -t autogram-cli-sign-test)"
trap 'rm -rf "$TMP_DIR"' EXIT

REQUEST_LOG="$TMP_DIR/request.json"
SOURCE="$TMP_DIR/source.pdf"
TARGET="$TMP_DIR/target.pdf"
APP_HELPERS="$TMP_DIR/Applications/Autogram macOS.app/Contents/Helpers"
MODULE_CACHE="$TMP_DIR/module-cache"

mkdir -p "$APP_HELPERS" "$MODULE_CACHE"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -parse-as-library -target arm64-apple-macosx27.0 -O "$RUNNER_SOURCE" -o "$APP_HELPERS/AutogramQuickActionRunner-arm64"

cat > "$TMP_DIR/helper.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    const char *request_path = getenv("REQUEST_LOG");
    FILE *request = request_path == NULL ? NULL : fopen(request_path, "w");
    int character;
    while ((character = fgetc(stdin)) != EOF) {
        if (request != NULL) {
            fputc(character, request);
        }
    }
    if (request != NULL) {
        fclose(request);
    }
    if (argc > 6 && strcmp(argv[6], "CERTIFICATES") == 0) {
        puts("{\"protocolVersion\":1,\"type\":\"certificates.available\",\"sessionId\":\"test\",\"payload\":{\"certificates\":[{\"serial\":\"certificate-1\",\"commonName\":\"Test Signer\"}]}}");
    }
    puts("{\"protocolVersion\":1,\"type\":\"session.completed\",\"sessionId\":\"test\",\"payload\":{}}");
    return 0;
}
C
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  clang -arch arm64 -O2 -Wall -Wextra -Werror "$TMP_DIR/helper.c" -o "$APP_HELPERS/AutogramCLI-arm64"

printf '%%PDF-1.4\n%%%%EOF\n' > "$SOURCE"

printf '1234' | HOME="$TMP_DIR" REQUEST_LOG="$REQUEST_LOG" "$SIGNER" \
  --driver secure_store \
  --key certificate-1 \
  --pin-stdin \
  --pdf-level PAdES_BASELINE_T \
  --tsa-server https://tsa.example.test \
  --target "$TARGET" \
  "$SOURCE" >/dev/null

grep -q '"operation":"SIGN"' "$REQUEST_LOG"
grep -q '"certificateSerial":"certificate-1"' "$REQUEST_LOG"
grep -q '"source":' "$REQUEST_LOG"

printf '1234' | HOME="$TMP_DIR" REQUEST_LOG="$REQUEST_LOG" "$SIGNER" \
  --driver secure_store \
  --list-keys \
  --pin-stdin > "$TMP_DIR/keys.tsv"
grep -q $'^AUTOGRAM_KEY\tcertificate-1\tTest Signer$' "$TMP_DIR/keys.tsv"

workflow_input_method="$(plutil -extract 'actions.0.action.ActionParameters.inputMethod' raw "$WORKFLOW")"
[[ "$workflow_input_method" == "1" ]] || {
  echo "Finder workflow must pass input as arguments (inputMethod=1)." >&2
  exit 1
}

if rg -n -e 'AUTOGRAM_NATIVE_BIN' -e 'AUTOGRAM_JSON_PYTHON' -e 'build/native' -e 'python3' "$SIGNER"; then
  echo "Bundled signer must not contain a development override, build fallback, or Python dependency." >&2
  exit 1
fi

if rg -n -e 'AUTOGRAM_NATIVE_BIN' -e 'AUTOGRAM_JSON_PYTHON' -e 'build/native' -e 'python3' \
  "$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow"; then
  echo "Bundled workflow must not contain a development override, build fallback, or Python dependency." >&2
  exit 1
fi

echo "CLI Quick Action native runner and machine request passed."
