# Autogram macOS CLI automation

Autogram has a human CLI and a versioned machine CLI. Use the machine CLI for non-interactive automation. Its protocol is documented in [Machine CLI protocol v1](machine-cli-protocol-v1.md).

## Machine CLI requirements

- macOS 27 or later.
- Apple silicon.
- Native ARM Autogram 2.7.5 or later.
- For I.CA tokens, I.CA SecureStore 8.3.1 or later.
- Every PKCS#11 dynamic library used by the machine CLI must contain an `arm64` slice.

Machine mode has no Intel, Rosetta, translated-runtime, JavaFX, or interactive fallback. Do not start it if any requirement is not met. A missing driver, service, platform capability, or required token is reported with exit code `69`.

## Starting machine mode

Pass a single JSON request through standard input and select the same operation on the command line:

```bash
printf '%s\n' '{"protocolVersion":1,"requestId":"example-1","operation":"CAPABILITIES","payload":{}}' \
  | AutogramApp --cli --machine-readable --protocol-version 1 --operation CAPABILITIES
```

Read JSON Lines only from standard output. Standard error is for local diagnostics and is not part of the protocol. The process exits after it has emitted and flushed its terminal event.

## Signing policy

Machine signing accepts PDF requests only and produces `PAdES_BASELINE_T`. A valid qualified timestamp is mandatory. The result must pass DSS validation with `TimestampQualification.QTSA`.

A TSA URL alone does not prove qualification. Verify the timestamp in the signed output against the applicable trusted list before accepting it as qualified.

## Human CLI

The existing `--cli` mode remains available for interactive use. Its arguments and output are separate from the machine protocol and are not a fallback for machine mode.
