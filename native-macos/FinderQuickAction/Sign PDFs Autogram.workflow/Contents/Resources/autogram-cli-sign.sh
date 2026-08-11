#!/usr/bin/env bash
set -euo pipefail

resolve_helper() {
  local candidate
  for candidate in \
    "${AUTOGRAM_NATIVE_BIN:-}" \
    "/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64" \
    "$HOME/Applications/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64" \
    "$(cd "$(dirname "$0")/../.." && pwd)/build/native/Autogram macOS.app/Contents/Helpers/AutogramCLI-arm64"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_python() {
  local candidate
  for candidate in "${AUTOGRAM_JSON_PYTHON:-}" /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
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

run_machine_request() {
  local python_bin="$1"
  local helper="$2"
  local operation="$3"
  shift 3

  "$python_bin" -c '
import json
import selectors
import subprocess
import sys

helper, operation, *args = sys.argv[1:]
pin = sys.stdin.read()
if operation == "CERTIFICATES":
    driver, = args
    payload = {"driver": driver, "pin": pin}
else:
    driver, certificate, source, target, level, tsa = args
    payload = {
        "driver": driver,
        "certificateSerial": certificate,
        "pin": pin,
        "signatureLevel": level,
        "timestamp": {"required": True, "servers": [tsa]},
        "files": [{"id": "file-1", "source": source, "target": target}],
    }
request = json.dumps({
    "protocolVersion": 1,
    "requestId": "autogram-quick-action",
    "operation": operation,
    "payload": payload,
}, ensure_ascii=False, separators=(",", ":")).encode()
pin = ""

process = subprocess.Popen(
    [helper, "--cli", "--machine-readable", "--protocol-version", "1", "--operation", operation],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    bufsize=0,
)
process.stdin.write(request)
process.stdin.close()
request = b""

selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ, "stdout")
selector.register(process.stderr, selectors.EVENT_READ, "stderr")
terminal = None
while selector.get_map():
    for key, _ in selector.select():
        data = key.fileobj.readline()
        if not data:
            selector.unregister(key.fileobj)
            continue
        text = data.decode("utf-8", errors="replace")
        print(text, end="", file=sys.stdout if key.data == "stdout" else sys.stderr, flush=True)
        if key.data == "stdout":
            try:
                event_type = json.loads(text).get("type")
            except json.JSONDecodeError:
                event_type = None
            if event_type in {"session.completed", "session.failed"}:
                terminal = event_type
                process.kill()
                break
    if terminal:
        break
process.wait()
raise SystemExit(0 if terminal == "session.completed" else 1)
' "$helper" "$operation" "$@"
}

parse_certificates() {
  "$1" -c '
import json
import sys
for line in sys.stdin:
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") != "certificates.available":
        continue
    for certificate in event.get("payload", {}).get("certificates", []):
        serial = str(certificate.get("serial", "")).strip()
        name = str(certificate.get("commonName", "")).replace("\\t", " ").replace("\\r", " ").replace("\\n", " ")
        if serial:
            print(f"AUTOGRAM_KEY\\t{serial}\\t{name}")
'
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

helper="$(resolve_helper || true)"
python_bin="$(resolve_python || true)"
[[ -n "$helper" ]] || { echo "Autogram macOS helper was not found." >&2; exit 69; }
[[ -n "$python_bin" ]] || { echo "Python 3 was not found." >&2; exit 69; }
[[ "$pin_stdin" -eq 1 ]] || { echo "--pin-stdin is required." >&2; exit 64; }
[[ -n "$driver" ]] || { echo "--driver is required." >&2; exit 64; }

if [[ "$list_keys" -eq 1 ]]; then
  response_file="$(mktemp -t autogram-certificates)"
  trap 'rm -f "$response_file"' EXIT
  set +e
  run_machine_request "$python_bin" "$helper" CERTIFICATES "$driver" > "$response_file"
  status=$?
  set -e
  parse_certificates "$python_bin" < "$response_file"
  if [[ "$status" -ne 0 ]]; then
    cat "$response_file" >&2
    exit "$status"
  fi
  exit 0
fi

[[ ${#sources[@]} -eq 1 ]] || { echo "Exactly one PDF source is required." >&2; exit 64; }
[[ -n "$certificate" ]] || { echo "--key is required." >&2; exit 64; }
[[ -n "$target" ]] || { echo "--target is required." >&2; exit 64; }
[[ -n "$tsa" ]] || { echo "--tsa-server is required." >&2; exit 64; }

echo "Signing: ${sources[0]}"
run_machine_request "$python_bin" "$helper" SIGN "$driver" "$certificate" \
  "$(absolute_path "${sources[0]}")" "$(absolute_path "$target")" "$level" "$tsa"
echo "Done."
