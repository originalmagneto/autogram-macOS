#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIGNER="$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/Resources/autogram-cli-sign.sh"
WORKFLOW="$REPO_ROOT/native-macos/FinderQuickAction/Sign PDFs Autogram.workflow/Contents/document.wflow"
RUNNER_SOURCE="$REPO_ROOT/scripts/native-macos/autogram-quick-action-runner.swift"

TMP_DIR="$(mktemp -d -t autogram-cli-sign-test)"
HELPER_PID_FILE="$TMP_DIR/helper.pid"

stop_helper() {
  if [[ -f "$HELPER_PID_FILE" ]]; then
    kill "$(<"$HELPER_PID_FILE")" 2>/dev/null || true
  fi
}

cleanup() {
  stop_helper
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void write_helper_pid(void) {
    const char *path = getenv("HELPER_PID_FILE");
    if (path == NULL) {
        return;
    }
    FILE *file = fopen(path, "w");
    if (file != NULL) {
        fprintf(file, "%d\n", getpid());
        fclose(file);
    }
}

static void write_large_standard_error(void) {
    char buffer[8192];
    memset(buffer, 'E', sizeof(buffer));
    for (int index = 0; index < 128; index++) {
        fwrite(buffer, 1, sizeof(buffer), stderr);
    }
    fflush(stderr);
}

int main(int argc, char *argv[]) {
    const char *mode = getenv("RUNNER_TEST_MODE");
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
    write_helper_pid();
    if (mode != NULL && strcmp(mode, "large-stderr-completed-waits") == 0) {
        write_large_standard_error();
        puts("{\"protocolVersion\":1,\"type\":\"certificates.available\",\"sessionId\":\"test\",\"payload\":{\"certificates\":[{\"serial\":\"certificate-1\",\"commonName\":\"Test Signer\"}]}}");
        puts("{\"protocolVersion\":1,\"type\":\"session.completed\",\"sessionId\":\"test\",\"payload\":{}}");
        fflush(stdout);
        for (;;) {
            pause();
        }
    }
    if (mode != NULL && strcmp(mode, "session-failed-waits") == 0) {
        fputs("helper failed\\n", stderr);
        fflush(stderr);
        puts("{\"protocolVersion\":1,\"type\":\"session.failed\",\"sessionId\":\"test\",\"payload\":{}}");
        fflush(stdout);
        for (;;) {
            pause();
        }
    }
    if (mode != NULL && strcmp(mode, "completed-ignores-sigterm") == 0) {
        signal(SIGTERM, SIG_IGN);
        puts("{\"protocolVersion\":1,\"type\":\"session.completed\",\"sessionId\":\"test\",\"payload\":{}}");
        fflush(stdout);
        for (;;) {
            pause();
        }
    }
    if (mode != NULL && strcmp(mode, "waits-for-cleanup") == 0) {
        for (;;) {
            pause();
        }
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

run_runner_with_deadline() {
  local mode="$1"
  local standard_output="$2"
  local standard_error="$3"
  local deadline runner_pid

  printf '1234' > "$TMP_DIR/pin"
  RUNNER_TEST_MODE="$mode" HELPER_PID_FILE="$HELPER_PID_FILE" \
    "$APP_HELPERS/AutogramQuickActionRunner-arm64" \
    --operation CERTIFICATES \
    --driver secure_store \
    --pin-stdin < "$TMP_DIR/pin" > "$standard_output" 2> "$standard_error" &
  runner_pid=$!
  deadline=$((SECONDS + 3))
  while kill -0 "$runner_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      kill "$runner_pid" 2>/dev/null || true
      wait "$runner_pid" 2>/dev/null || true
      echo "Quick Action runner did not return after terminal helper event." >&2
      return 1
    fi
    sleep 0.1
  done
  set +e
  wait "$runner_pid"
  RUNNER_STATUS=$?
  set -e
}

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

run_runner_with_deadline \
  large-stderr-completed-waits \
  "$TMP_DIR/completed.out" \
  "$TMP_DIR/completed.err"
[[ "$RUNNER_STATUS" -eq 0 ]]
grep -q $'^AUTOGRAM_KEY\tcertificate-1\tTest Signer$' "$TMP_DIR/completed.out"
[[ "$(wc -c < "$TMP_DIR/completed.err")" -eq 1048576 ]]

run_runner_with_deadline \
  session-failed-waits \
  "$TMP_DIR/failed.out" \
  "$TMP_DIR/failed.err"
[[ "$RUNNER_STATUS" -ne 0 ]]
grep -q 'helper failed' "$TMP_DIR/failed.err"

run_runner_with_deadline \
  completed-ignores-sigterm \
  "$TMP_DIR/ignores-sigterm.out" \
  "$TMP_DIR/ignores-sigterm.err"
[[ "$RUNNER_STATUS" -eq 0 ]]
[[ "$(<"$HELPER_PID_FILE")" =~ ^[0-9]+$ ]]
! kill -0 "$(<"$HELPER_PID_FILE")" 2>/dev/null

rm -f "$HELPER_PID_FILE"
RUNNER_TEST_MODE=waits-for-cleanup HELPER_PID_FILE="$HELPER_PID_FILE" \
  "$APP_HELPERS/AutogramCLI-arm64" </dev/null >/dev/null 2>/dev/null &
helper_pid=$!
while [[ ! -s "$HELPER_PID_FILE" ]]; do
  sleep 0.01
done
stop_helper
wait "$helper_pid" 2>/dev/null || true
! kill -0 "$(<"$HELPER_PID_FILE")" 2>/dev/null

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
