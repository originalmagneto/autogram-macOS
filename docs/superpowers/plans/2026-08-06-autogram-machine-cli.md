# Autogram Machine CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a versioned, non-interactive JSON Lines interface that exposes Autogram capabilities, drivers, certificates, PDF inspection, and batch PAdES Baseline T signing to the native macOS application.

**Architecture:** A new `digital.slovensko.autogram.ui.machine` adapter parses one JSON request from standard input and emits typed JSON Lines events to standard output. It reuses the existing driver, token, signing, DSS validation, and timestamp code while leaving the human CLI behavior unchanged.

**Tech Stack:** Java 25, Gson 2.14, Apache Commons CLI 1.11, DSS 6.4, JUnit 6, Mockito 5, Maven

## Global Constraints

- The first release signs PDF only.
- Every successful output is `PAdES_BASELINE_T`.
- Every successful output must contain a timestamp whose DSS qualification is `TimestampQualification.QTSA`.
- The machine protocol version is exactly `1`.
- PIN values are accepted only through standard input and are never logged.
- Human CLI output and behavior must remain backward compatible.
- Native macOS machine mode targets one ARM64 Autogram helper and contains no Intel, Rosetta, or x86_64 compatibility branch.
- One failed file must not stop later files in the batch.
- Original files must never be overwritten.
- Comments and documentation use English and contain no em dash characters.
- `AGENTS.md` and `CLAUDE.md` remain identical.

---

## Locked File Map

- `protocol/v1/schema/request.schema.json`: request envelope schema.
- `protocol/v1/schema/event.schema.json`: event envelope schema.
- `protocol/v1/fixtures/*.jsonl`: shared Java and Swift contract fixtures.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineOperation.java`: supported operation enum.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineRequest.java`: request envelope.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineEvent.java`: event envelope.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineProtocolCodec.java`: strict Gson codec.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineProtocolException.java`: typed protocol rejection.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineEventWriter.java`: synchronized JSON Lines writer.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineError.java`: stable error payload.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineErrorMapper.java`: exception to error-code mapping.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineCliApp.java`: operation dispatcher and lifecycle.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineRequestValidator.java`: protocol and path validation.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineDriverService.java`: capabilities, drivers, and certificates.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`: DSS PDF signature inspection.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineTrustService.java`: bounded EU trusted-list initialization.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineSigningService.java`: token session and per-file signing loop.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineSettings.java`: request-scoped settings.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineSecretUI.java`: PIN provider with no prompts.
- `src/main/java/digital/slovensko/autogram/ui/machine/MachineFileResponder.java`: explicit target writer and callback.
- `src/test/java/digital/slovensko/autogram/ui/machine/*Test.java`: focused machine-mode tests.

### Shared Java Interfaces

```java
public enum MachineOperation {
    CAPABILITIES, DRIVERS, CERTIFICATES, INSPECT, SIGN
}

public record MachineRequest(
        int protocolVersion,
        String requestId,
        MachineOperation operation,
        JsonObject payload) {}

public record MachineEvent(
        int protocolVersion,
        String type,
        String sessionId,
        String emittedAt,
        String fileId,
        JsonObject payload) {}

public record MachineError(
        String code,
        String messageKey,
        String fallbackMessage,
        boolean retryable,
        String recovery) {}
```

### Operation Payloads

```java
public record CertificateRequest(String driver, char[] pin) {}

public record InspectRequest(List<MachineFile> files) {}

public record SignRequest(
        String driver,
        String certificateSerial,
        char[] pin,
        String signatureLevel,
        QualifiedTimestampRequest timestamp,
        List<MachineFile> files) {}

public record QualifiedTimestampRequest(boolean required, List<String> servers) {}

public record MachineFile(String id, String source, String target) {}
```

### Task 1: Freeze Protocol Version 1

**Files:**
- Create: `protocol/v1/schema/request.schema.json`
- Create: `protocol/v1/schema/event.schema.json`
- Create: `protocol/v1/fixtures/capabilities-request.json`
- Create: `protocol/v1/fixtures/session-events.jsonl`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineOperation.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineRequest.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineEvent.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineProtocolCodec.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineProtocolException.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineProtocolCodecTest.java`

**Interfaces:**
- Consumes: Gson from `pom.xml`.
- Produces: `MachineProtocolCodec.decodeRequest(Reader)` and `encodeEvent(MachineEvent)`.

- [ ] **Step 1: Write the failing codec tests**

```java
@Test
void decodesVersionOneCapabilitiesFixture() throws Exception {
    try (var reader = Files.newBufferedReader(Path.of("protocol/v1/fixtures/capabilities-request.json"))) {
        var request = new MachineProtocolCodec().decodeRequest(reader);
        assertEquals(1, request.protocolVersion());
        assertEquals(MachineOperation.CAPABILITIES, request.operation());
        assertEquals("request-1", request.requestId());
    }
}

@Test
void rejectsTrailingInput() {
    var input = new StringReader("{\"protocolVersion\":1,\"requestId\":\"a\",\"operation\":\"CAPABILITIES\",\"payload\":{}} {} ");
    assertThrows(MachineProtocolException.class, () -> new MachineProtocolCodec().decodeRequest(input));
}
```

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `./mvnw -Psystem-jdk -Dtest=MachineProtocolCodecTest test`

Expected: compilation fails because the machine protocol classes do not exist.

- [ ] **Step 3: Add exact protocol fixtures and DTOs**

`capabilities-request.json`:

```json
{"protocolVersion":1,"requestId":"request-1","operation":"CAPABILITIES","payload":{}}
```

The request schema must require `protocolVersion`, `requestId`, `operation`, and `payload`, reject additional top-level properties, and restrict `operation` to the five enum values.

- [ ] **Step 4: Implement strict single-object decoding and event encoding**

```java
public final class MachineProtocolCodec {
    public static final int VERSION = 1;
    private final Gson gson = new GsonBuilder().disableHtmlEscaping().create();

    public MachineRequest decodeRequest(Reader reader) {
        var jsonReader = new JsonReader(reader);
        var request = gson.fromJson(jsonReader, MachineRequest.class);
        if (request == null || jsonReader.peek() != JsonToken.END_DOCUMENT)
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        return request;
    }

    public String encodeEvent(MachineEvent event) {
        return gson.toJson(event);
    }
}
```

- [ ] **Step 5: Run the test and commit**

Run: `./mvnw -Psystem-jdk -Dtest=MachineProtocolCodecTest test`

Expected: PASS.

Commit: `feat(cli): define machine protocol v1`

### Task 2: Route Machine Mode Without Changing Human CLI

**Files:**
- Modify: `src/main/java/digital/slovensko/autogram/core/AppStarter.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineCliApp.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineEventWriter.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineRequestValidator.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineCliAppTest.java`
- Test: `src/test/java/digital/slovensko/autogram/core/AppStarterMachineOptionsTest.java`

**Interfaces:**
- Consumes: `MachineProtocolCodec` from Task 1.
- Produces: `MachineCliApp.start(CommandLine, Reader, PrintWriter, PrintWriter): int`.

- [ ] **Step 1: Add failing routing and version tests**

```java
@Test
void rejectsUnsupportedProtocolVersionAsJsonEvent() {
    var stdin = new StringReader("{\"protocolVersion\":2,\"requestId\":\"r\",\"operation\":\"CAPABILITIES\",\"payload\":{}}");
    var stdout = new StringWriter();
    var code = MachineCliApp.start(commandLine(), stdin, new PrintWriter(stdout), new PrintWriter(new StringWriter()));
    assertEquals(64, code);
    assertTrue(stdout.toString().contains("PROTOCOL_UNSUPPORTED_VERSION"));
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `./mvnw -Psystem-jdk -Dtest=MachineCliAppTest,AppStarterMachineOptionsTest test`

Expected: FAIL because machine routing is absent.

- [ ] **Step 3: Add CLI options and dispatch**

Add options `--machine-readable`, `--protocol-version`, and `--operation`. When `--cli --machine-readable` is present, require all three and call `MachineCliApp.start(...)`; otherwise call the existing `CliApp.start(cmd)` unchanged. Reject the request when the command-line operation and JSON envelope operation do not match.

```java
if (cmd.hasOption("machine-readable")) {
    exitCode = MachineCliApp.start(cmd,
            new InputStreamReader(System.in, StandardCharsets.UTF_8),
            new PrintWriter(System.out, true, StandardCharsets.UTF_8),
            new PrintWriter(System.err, true, StandardCharsets.UTF_8));
} else {
    exitCode = CliApp.start(cmd);
}
```

- [ ] **Step 4: Implement synchronized event output**

`MachineEventWriter.write(type, sessionId, fileId, payload)` must create an ISO-8601 UTC timestamp, write exactly one JSON object plus `\n`, and flush. It must never receive or serialize the request object.

- [ ] **Step 5: Run machine and existing CLI tests**

Run: `./mvnw -Psystem-jdk -Dtest=MachineCliAppTest,AppStarterMachineOptionsTest,CliHeadlessSettingsTest test`

Expected: PASS.

Commit: `feat(cli): route versioned machine mode`

### Task 3: Implement Capabilities, Drivers, and Certificates

**Files:**
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineSettings.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineSecretUI.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineDriverService.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineCliApp.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineDriverServiceTest.java`

**Interfaces:**
- Consumes: `DefaultDriverDetector`, `PasswordManager`, `CliKeySelector`, and request DTOs.
- Produces: driver payloads with `id`, `name`, `path`, and `installed`; certificate payloads with `serial`, `commonName`, `validFrom`, `validUntil`, and `expired`.

- [ ] **Step 1: Write failing service tests with fake detectors**

```java
@Test
void capabilitiesForcePdfBaselineTAndQualifiedTimestamp() {
    var payload = service.capabilities();
    assertEquals(List.of("PAdES_BASELINE_T"), strings(payload, "signatureLevels"));
    assertTrue(payload.getAsJsonObject("timestampPolicy").get("required").getAsBoolean());
}

@Test
void certificateResponseDoesNotContainPin() {
    var json = codec.encodeEvent(service.certificates(fakeDriver(), "1234".toCharArray()));
    assertFalse(json.contains("1234"));
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `./mvnw -Psystem-jdk -Dtest=MachineDriverServiceTest test`

- [ ] **Step 3: Implement request-scoped settings and secret UI**

`MachineSecretUI` implements `UI`, returns a clone of its request PIN from both password methods, throws if any interactive consent or selection method is reached, and clears its internal `char[]` with `Arrays.fill(secret, '\0')` in `close()`.

- [ ] **Step 4: Implement driver and certificate operations**

Filter by exact driver short name. Open the token in try-with-resources, map certificates, then clear the request PIN in `finally`. Never send driver paths in shareable errors.

- [ ] **Step 5: Run tests and commit**

Run: `./mvnw -Psystem-jdk -Dtest=MachineDriverServiceTest,MachineCliAppTest test`

Expected: PASS.

Commit: `feat(cli): expose drivers and certificates`

### Task 4: Add DSS PDF Inspection and Qualification Evaluation

**Files:**
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineInspectionService.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineTrustService.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/TimestampQualificationEvaluator.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineCliApp.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineInspectionServiceTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/TimestampQualificationEvaluatorTest.java`

**Interfaces:**
- Consumes: `SignatureValidator`, DSS `SimpleReport`, and `TimestampQualification.QTSA`.
- Produces: per-signature metadata and `qualifiedTimestampValid: boolean`.

- [ ] **Step 1: Write failing qualification tests**

```java
@Test
void requiresAtLeastOneValidQualifiedSignatureTimestamp() {
    var report = mock(SimpleReport.class);
    when(report.getSignatureTimestamps("sig-1")).thenReturn(List.of(timestamp("ts-1")));
    when(report.isValid("ts-1")).thenReturn(true);
    when(report.getTimestampQualification("ts-1")).thenReturn(TimestampQualification.QTSA);
    assertTrue(new TimestampQualificationEvaluator().hasValidQualifiedTimestamp(report, "sig-1"));
}

@Test
void rejectsOrdinaryTsaQualification() {
    var report = reportWith(TimestampQualification.TSA, true);
    assertFalse(new TimestampQualificationEvaluator().hasValidQualifiedTimestamp(report, "sig-1"));
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest,TimestampQualificationEvaluatorTest test`

- [ ] **Step 3: Implement batch report mapping**

Decode the locked `InspectRequest(List<MachineFile> files)` payload. For each file emit file-scoped inspection success or failure events and continue after a file failure. For every signature ID return format, signer display name, signing time, validity, indication, and timestamp entries. For every timestamp return production time, producer, validity, and qualification. Keep signer-certificate qualification separate from timestamp qualification.

- [ ] **Step 4: Initialize EU trusted lists with a bounded lifecycle**

`MachineSettings` must initialize the same non-null EU trusted-list collection used by the existing human application. `MachineTrustService` creates a dedicated executor, calls `SignatureValidator.initialize(executor, settings.getTrustedList())`, waits up to 60 seconds for `areTLsLoaded()`, cancels unfinished initialization, calls `shutdownNow()`, and awaits bounded executor termination. Emit `TRUSTED_LIST_UNAVAILABLE` and fail closed when no trusted list is loaded before the deadline.

- [ ] **Step 5: Add post-signing inspection fixture**

Use `src/test/resources/digital/slovensko/autogram/sample_signed.pdf` for structural inspection. Use mocked DSS reports for QTSA policy because automated tests must not depend on live EU trusted-list downloads.

- [ ] **Step 6: Run tests and commit**

Run: `./mvnw -Psystem-jdk -Dtest=MachineInspectionServiceTest,TimestampQualificationEvaluatorTest test`

Expected: PASS.

Commit: `feat(cli): expose PDF signature inspection`

### Task 5: Implement Explicit-Target Batch Signing

**Files:**
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineSigningService.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineFileResponder.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineRequestValidator.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineCliApp.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineRequestValidatorTest.java`

**Interfaces:**
- Consumes: `SignRequest`, `DefaultDriverDetector`, `SigningJob`, `SigningKey`, and Task 4 inspection.
- Produces: `file.signingStarted`, `file.completed`, `file.failed`, and final session events.

- [ ] **Step 1: Write failing policy and continuation tests**

```java
@Test
void rejectsBaselineBEvenWhenRequestedByCaller() {
    var request = signRequest("PAdES_BASELINE_B", files("a"));
    assertEquals("SIGNATURE_LEVEL_REQUIRED", validator.validateSign(request).code());
}

@Test
void continuesAfterOneFileFails() {
    service.sign(signRequestFor("bad.pdf", "good.pdf"));
    assertEquals(List.of("file.failed", "file.completed", "session.completed"), writer.eventTypes());
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `./mvnw -Psystem-jdk -Dtest=MachineSigningServiceTest,MachineRequestValidatorTest test`

- [ ] **Step 3: Validate safe source-target pairs**

Reject missing files, non-PDF input, source equal to target, existing targets, duplicate targets, parent traversal after canonicalization, and non-absolute paths. Require `timestamp.required == true`, at least one supported TSA URL, and `PAdES_BASELINE_T`.

- [ ] **Step 4: Implement one token session and per-file loop**

Open the selected token once, select exactly one key by certificate serial, create one `SigningKey`, then build and sign each `SigningJob` independently. `MachineFileResponder` saves to the explicit target and invokes a completion callback. Catch each file error, emit `file.failed`, and continue.

- [ ] **Step 5: Validate every produced artifact**

After save, verify `%PDF-`, `%%EOF`, PAdES level, and a valid `QTSA` timestamp through Task 4. Delete the target and emit `OUTPUT_VALIDATION_FAILED` if any check fails.

- [ ] **Step 6: Clear secrets and close the token**

Use `finally` to fill every request PIN array with zero, close the token, and emit one final session event. No exception may print the request object.

- [ ] **Step 7: Run tests and commit**

Run: `./mvnw -Psystem-jdk -Dtest=MachineSigningServiceTest,MachineRequestValidatorTest,SigningJobTests test`

Expected: PASS.

Commit: `feat(cli): add machine batch PDF signing`

### Task 6: Stabilize Errors, Shutdown, and Documentation

**Files:**
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineError.java`
- Create: `src/main/java/digital/slovensko/autogram/ui/machine/MachineErrorMapper.java`
- Modify: `src/main/java/digital/slovensko/autogram/ui/machine/MachineCliApp.java`
- Modify: `src/main/java/digital/slovensko/autogram/core/AppStarter.java`
- Modify: `docs/macos-cli-automation.md`
- Create: `docs/machine-cli-protocol-v1.md`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachineErrorMapperTest.java`
- Test: `src/test/java/digital/slovensko/autogram/ui/machine/MachinePrivacyTest.java`

**Interfaces:**
- Consumes: all machine services.
- Produces: stable error codes, documented exit codes, and deterministic process completion.

- [ ] **Step 1: Write failing redaction and exit tests**

```java
@Test
void errorOutputExcludesPinAndAbsolutePath() {
    var event = mapper.map(new PINIncorrectException(), Path.of("/private/client.pdf"), "1234".toCharArray());
    var json = codec.encodeEvent(event);
    assertFalse(json.contains("1234"));
    assertFalse(json.contains("/private/client.pdf"));
    assertTrue(json.contains("PIN_INCORRECT"));
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `./mvnw -Psystem-jdk -Dtest=MachineErrorMapperTest,MachinePrivacyTest test`

- [ ] **Step 3: Implement stable mappings and exit codes**

Use `0` for a completed request, including partial file failures described by events; `64` for protocol or request errors; `69` for unavailable driver or service; and `70` for an internal machine-mode failure. Unknown exceptions map to `INTERNAL_ERROR` without class names or stack traces on standard output.

- [ ] **Step 4: Enforce deterministic ARM64 shutdown**

Machine mode must flush its terminal event, close resources, and terminate deterministically in the native ARM64 runtime. Do not add Intel-specific exit handling, translated-runtime fallbacks, or rules that convert an abnormal helper exit into success.

- [ ] **Step 5: Document the complete protocol**

Include exact requests, events, errors, exit codes, privacy rules, and protocol-version compatibility. State that a TSA URL alone does not prove qualification and that `QTSA` validation is mandatory.

- [ ] **Step 6: Run full verification**

Run:

```bash
export JAVA_HOME="$(/usr/libexec/java_home -v 25)"
export PATH="$JAVA_HOME/bin:$PATH"
./mvnw -Psystem-jdk test
git diff --check
rg -n $'\u2014|/Users/|BEGIN .*PRIVATE KEY|password\\s*=' protocol docs/machine-cli-protocol-v1.md src/main/java/digital/slovensko/autogram/ui/machine
```

Expected: 0 test failures, clean diff, and no sensitive matches. Replace the local `JAVA_HOME` example with environment-neutral commands before committing documentation.

- [ ] **Step 7: Commit**

Commit: `docs(cli): document machine protocol v1`

## Completion Gate

- All existing 347 baseline tests still pass.
- New machine-mode tests pass without live cards or network services.
- Human CLI focused tests pass unchanged.
- Protocol fixtures decode in both Java and Swift.
- No request payload, PIN, client path, or raw exception reaches machine output.
- SOL reviews the protocol contract before native integration begins.
- Luna performs a read-only privacy and contract audit.
