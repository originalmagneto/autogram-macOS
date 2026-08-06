package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonParser;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.core.SignedDocument;
import digital.slovensko.autogram.drivers.TokenDriver;
import eu.europa.esig.dss.enumerations.Indication;
import eu.europa.esig.dss.enumerations.SignatureLevel;
import eu.europa.esig.dss.model.InMemoryDocument;
import eu.europa.esig.dss.simplereport.SimpleReport;
import eu.europa.esig.dss.simplereport.jaxb.XmlTimestamp;
import eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection;
import eu.europa.esig.dss.token.Pkcs12SignatureToken;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.KeyStore;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class MachineSigningServiceTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void continuesAfterOneFileFails() throws Exception {
        var writer = new RecordingWriter();
        var session = new FakeSession((file, completed) -> {
            if (file.id().equals("bad")) {
                throw new IllegalStateException("sensitive failure");
            }
            Files.writeString(Path.of(file.target()), "%PDF-1.7\ngood\n%%EOF");
            completed.run();
        });
        var service = new MachineSigningService(writer.writer(), request -> session, path -> true);
        var pin = "1234".toCharArray();

        service.sign("request-1", request(pin, file("bad", "bad.pdf", "bad-signed.pdf"),
                file("good", "good.pdf", "good-signed.pdf")));

        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "file.signingStarted",
                "file.completed", "session.completed"), writer.eventTypes());
        assertTrue(session.closed);
        assertTrue(Arrays.equals(new char[pin.length], pin));
        assertFalse(writer.serialized().contains("sensitive failure"));
    }

    @Test
    void deletesInvalidOutputBeforeReportingOutputValidationFailure() throws Exception {
        var writer = new RecordingWriter();
        var target = target("invalid-signed.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(Path.of(file.target()), "%PDF-1.7\ninvalid\n%%EOF");
            completed.run();
        }), path -> false);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertFalse(Files.exists(target));
        assertEquals("OUTPUT_VALIDATION_FAILED", writer.payloadCode(2));
        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "session.completed"),
                writer.eventTypes());
    }

    @Test
    void reportsEveryFileWhenTokenSetupFailsAndClearsTheRequestPin() throws Exception {
        var writer = new RecordingWriter();
        var pin = "1234".toCharArray();
        var service = new MachineSigningService(writer.writer(), request -> {
            throw new IllegalStateException("token at /private/card 1234");
        }, path -> true);

        service.sign("request-1", request(pin, file("one", "one.pdf", "one-signed.pdf"),
                file("two", "two.pdf", "two-signed.pdf")));

        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "file.signingStarted",
                "file.failed", "session.failed"), writer.eventTypes());
        assertTrue(Arrays.equals(new char[pin.length], pin));
        assertFalse(writer.serialized().contains("/private/card"));
        assertFalse(writer.serialized().contains("1234"));
    }

    @Test
    void emitsNoDuplicateFileEventsWhenSessionCloseFails() throws Exception {
        var writer = new RecordingWriter();
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(Path.of(file.target()), "%PDF-1.7\ngood\n%%EOF");
            completed.run();
        }, true), path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "signed.pdf")));

        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.failed"),
                writer.eventTypes());
    }

    @Test
    void explicitTargetResponderNeverDeletesAnExistingTarget() throws Exception {
        var source = Files.writeString(temporaryDirectory.resolve("source.pdf"), "%PDF-1.7\nsource\n%%EOF");
        var target = Files.writeString(target("existing.pdf"), "%PDF-1.7\nexisting\n%%EOF");
        var responder = new MachineFileResponder(target, ignored -> { });

        assertThrows(MachineProtocolException.class,
                () -> responder.onDocumentSigned(new SignedDocument(new InMemoryDocument("replacement".getBytes()), null)));

        assertEquals("%PDF-1.7\nsource\n%%EOF", Files.readString(source));
        assertEquals("%PDF-1.7\nexisting\n%%EOF", Files.readString(target));
    }

    @Test
    void completionCallbackFailureLeavesThePrivateOwnerToCleanItsTarget() throws Exception {
        var target = target("callback-failed.pdf");
        var responder = new MachineFileResponder(target, ignored -> {
            throw new IllegalStateException("callback failure");
        });

        assertThrows(MachineProtocolException.class,
                () -> responder.onDocumentSigned(new SignedDocument(new InMemoryDocument("replacement".getBytes()), null)));

        assertTrue(Files.exists(target));
    }

    @Test
    void signingFailureNeverDeletesAConcurrentUserTarget() throws Exception {
        var writer = new RecordingWriter();
        var target = target("late-collision.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(target, "%PDF-1.7\nother process\n%%EOF");
            throw new IllegalStateException("late collision");
        }), path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertEquals("%PDF-1.7\nother process\n%%EOF", Files.readString(target));
        assertEquals("SIGNING_FAILED", writer.payloadCode(2));
    }

    @Test
    void signingFailureNeverDeletesAConcurrentUserSymlink() throws Exception {
        var writer = new RecordingWriter();
        var target = target("symlink-replacement.pdf");
        var unrelated = Files.writeString(target("unrelated.pdf"), "%PDF-1.7\nunrelated\n%%EOF");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.createSymbolicLink(target, unrelated);
            throw new IllegalStateException("late symlink");
        }), path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertTrue(Files.isSymbolicLink(target));
        assertEquals("%PDF-1.7\nunrelated\n%%EOF", Files.readString(unrelated));
        assertEquals("SIGNING_FAILED", writer.payloadCode(2));
    }

    @Test
    void signsAnOwnedSnapshotInsteadOfAPathReopenedAfterPreparation() throws Exception {
        var writer = new RecordingWriter();
        var source = Files.writeString(temporaryDirectory.resolve("source.pdf"), "%PDF-1.7\noriginal\n%%EOF");
        var target = target("signed.pdf");
        var sourceSeenBySigner = new AtomicReference<String>();
        var sessionOpened = new AtomicReference<Boolean>(false);
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            sourceSeenBySigner.set(Files.readString(Path.of(file.source())));
            Files.writeString(Path.of(file.target()), "%PDF-1.7\nsigned\n%%EOF");
            completed.run();
        }), path -> true, () -> {
            try {
                assertEquals("%PDF-1.7\noriginal\n%%EOF", Files.readString(source));
                Files.writeString(source, "%PDF-1.7\nreplaced\n%%EOF", StandardOpenOption.TRUNCATE_EXISTING);
            } catch (java.io.IOException exception) {
                throw new IllegalStateException(exception);
            }
            sessionOpened.set(true);
        });

        service.sign("request-1", request("1234".toCharArray(),
                new MachineFile("one", source.toRealPath().toString(), target.toString())));

        assertTrue(sessionOpened.get());
        assertEquals("%PDF-1.7\noriginal\n%%EOF", sourceSeenBySigner.get());
        assertEquals("%PDF-1.7\nsigned\n%%EOF", Files.readString(target));
    }

    @Test
    void publishesOnlyAfterRealPdfOutputValidationSucceeds() throws Exception {
        var writer = new RecordingWriter();
        var target = target("published-after-validation.pdf");
        var targetSeenDuringSigning = new AtomicReference<Boolean>();
        var inspection = new MachineInspectionService(path -> qualifiedReport(), content ->
                new String(content, java.nio.charset.StandardCharsets.ISO_8859_1).contains("signed")
                        ? qualifiedReport("new") : qualifiedReport());
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            targetSeenDuringSigning.set(Files.exists(target));
            Files.writeString(Path.of(file.target()), "%PDF-1.7\nsigned\n%%EOF");
            completed.run();
        }), new MachineSigningService.PdfOutputValidator(inspection));

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertFalse(targetSeenDuringSigning.get());
        assertEquals("%PDF-1.7\nsigned\n%%EOF", Files.readString(target));
        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.completed"),
                writer.eventTypes());
    }

    @Test
    void stagedReplacementCannotChangeTheBytesPublishedAfterValidation() throws Exception {
        var writer = new RecordingWriter();
        var target = target("stable-publication.pdf");
        var stagedOutput = new AtomicReference<Path>();
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            stagedOutput.set(Path.of(file.target()));
            Files.writeString(stagedOutput.get(), "%PDF-1.7\nvalidated-A\n%%EOF");
            completed.run();
        }), path -> {
            Files.writeString(stagedOutput.get(), "%PDF-1.7\nreplacement-B\n%%EOF");
            return true;
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertEquals("%PDF-1.7\nvalidated-A\n%%EOF", Files.readString(target));
    }

    @Test
    void validationFailureNeverDeletesAConcurrentUserTargetReplacement() throws Exception {
        var writer = new RecordingWriter();
        var target = target("concurrent-user-target.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(Path.of(file.target()), "%PDF-1.7\ninvalid\n%%EOF");
            completed.run();
        }), path -> {
            Files.writeString(target, "%PDF-1.7\nuser-replacement\n%%EOF");
            return false;
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertEquals("%PDF-1.7\nuser-replacement\n%%EOF", Files.readString(target));
        assertEquals("OUTPUT_VALIDATION_FAILED", writer.payloadCode(2));
    }

    @Test
    void validationFailurePreservesAReplacementAndReportsAnExplicitCleanupFailure() throws Exception {
        var writer = new RecordingWriter();
        var target = target("replaced.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(Path.of(file.target()), "%PDF-1.7\ninvalid\n%%EOF");
            completed.run();
        }), content -> {
            Files.writeString(target, "%PDF-1.7\nreplacement\n%%EOF");
            return false;
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertEquals("%PDF-1.7\nreplacement\n%%EOF", Files.readString(target));
        assertEquals("OUTPUT_VALIDATION_FAILED", writer.payloadCode(2));
    }

    @Test
    void validationExceptionDeletesOnlyTheOwnedOutputAndReportsValidationFailure() throws Exception {
        var writer = new RecordingWriter();
        var target = target("validator-threw.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(Path.of(file.target()), "%PDF-1.7\nsigned\n%%EOF");
            completed.run();
        }), path -> {
            throw new java.io.IOException("report unavailable");
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertFalse(Files.exists(target));
        assertEquals("OUTPUT_VALIDATION_FAILED", writer.payloadCode(2));
    }

    @Test
    void preparationCleanupFailureIsReportedBeforeTokenWork() throws Exception {
        var writer = new RecordingWriter();
        var tokenOpened = new AtomicBoolean();
        var service = new MachineSigningService(writer.writer(), request -> {
            tokenOpened.set(true);
            throw new AssertionError("Token must not open after preparation cleanup failure");
        }, content -> true, () -> { }, targetParent -> new MachineSigningService.StagingWorkspace() {
            @Override
            public Path createFile(String prefix, String suffix) throws java.io.IOException {
                throw new java.io.IOException("identity capture failed");
            }

            @Override
            public Path newOutputPath(String prefix, String suffix) {
                throw new AssertionError("staging output must not be allocated");
            }

            @Override
            public boolean cleanup() {
                return false;
            }
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "target.pdf")));

        assertFalse(tokenOpened.get());
        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "session.failed"),
                writer.eventTypes());
        assertEquals("OUTPUT_CLEANUP_FAILED", writer.payloadCode(2));
    }

    @Test
    void sourceSetupFailureCleansThePrivateWorkspaceBeforeTokenWork() throws Exception {
        var writer = new RecordingWriter();
        var tokenOpened = new AtomicBoolean();
        var service = new MachineSigningService(writer.writer(), request -> {
            tokenOpened.set(true);
            throw new AssertionError("Token must not open after source setup failure");
        }, content -> true, () -> { }, targetParent -> {
            var workspace = MachineSigningService.PrivateWorkspace.create(targetParent);
            return new MachineSigningService.StagingWorkspace() {
                @Override
                public Path createFile(String prefix, String suffix) throws java.io.IOException {
                    workspace.createFile(prefix, suffix);
                    throw new java.io.IOException("identity capture failed");
                }

                @Override
                public Path newOutputPath(String prefix, String suffix) throws java.io.IOException {
                    return workspace.newOutputPath(prefix, suffix);
                }

                @Override
                public boolean cleanup() {
                    return workspace.cleanup();
                }
            };
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "target.pdf")));

        assertFalse(tokenOpened.get());
        try (var entries = Files.list(temporaryDirectory.toRealPath())) {
            assertFalse(entries.anyMatch(path -> path.getFileName().toString().startsWith(".autogram-machine-")));
        }
        assertEquals("SIGNING_UNAVAILABLE", writer.payloadCode(2));
    }

    @Test
    void rejectsNonPdfSourceDuringSingleOpenPreparationBeforeTokenWork() throws Exception {
        var writer = new RecordingWriter();
        var source = Files.writeString(temporaryDirectory.resolve("not-pdf.pdf"), "not a PDF").toRealPath();
        var target = target("not-pdf-signed.pdf");
        var tokenOpened = new AtomicBoolean();
        var service = new MachineSigningService(writer.writer(), request -> {
            tokenOpened.set(true);
            throw new AssertionError("Token must not open for a non-PDF source");
        }, content -> true);

        service.sign("request-1", request("1234".toCharArray(),
                new MachineFile("one", source.toString(), target.toString())));

        assertFalse(tokenOpened.get());
        assertFalse(Files.exists(target));
        assertEquals("SIGNING_UNAVAILABLE", writer.payloadCode(2));
    }

    @Test
    void outputValidatorAcceptsOnlyANewFullyQualifiedBaselineTSignature() throws Exception {
        var target = Files.writeString(target("validated.pdf"), "%PDF-1.7\nvalidated\n%%EOF");
        var rejected = Files.writeString(target("rejected.pdf"), "%PDF-1.7\nrejected\n%%EOF");
        var existing = qualifiedReport("existing");
        var added = qualifiedReport("existing", "new");
        var invalidNew = qualifiedReport("existing", "new");
        when(invalidNew.isValid("new")).thenReturn(false);
        var validator = new MachineSigningService.PdfOutputValidator(new MachineInspectionService(path -> existing,
                content -> new String(content, java.nio.charset.StandardCharsets.ISO_8859_1).contains("before")
                        ? existing : new String(content, java.nio.charset.StandardCharsets.ISO_8859_1).contains("rejected")
                                ? invalidNew : added));
        var before = "%PDF-1.7\nbefore\n%%EOF".getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);

        assertEquals(java.util.Set.of("existing"), validator.signatureIds(before));
        assertTrue(validator.isValid(Files.readAllBytes(target), java.util.Set.of("existing")));
        assertFalse(validator.isValid(Files.readAllBytes(rejected), java.util.Set.of("existing")));
        assertFalse(validator.isValid(Files.readAllBytes(target), java.util.Set.of("existing", "new")));
    }

    @Test
    void outputValidatorRejectsSymlinkPaths() throws Exception {
        var document = Files.writeString(target("regular.pdf"), "%PDF-1.7\nregular\n%%EOF");
        var link = target("linked.pdf");
        Files.createSymbolicLink(link, document);
        var validator = new MachineSigningService.PdfOutputValidator(new MachineInspectionService(path -> qualifiedReport(),
                content -> qualifiedReport("new")));

        assertThrows(java.io.IOException.class, () -> validator.isValid(link, java.util.Set.of()));
    }

    @Test
    void defaultSessionFactorySelectsExactlyOneSerialAndClosesOneToken() throws Exception {
        var driver = new TestTokenDriver("test");
        var request = request("1234".toCharArray(), file("one", "source.pdf", "signed.pdf"));
        var serial = driver.serial();
        request = new SignRequest("test", serial, request.pin(), request.signatureLevel(), request.timestamp(), request.files());
        var factory = new MachineSigningService.DefaultSessionFactory(() -> List.of(driver), new MachineSettings(true),
                PasswordManager::new);

        try (var session = factory.apply(request)) {
            assertTrue(driver.created);
        }

        assertEquals(1, driver.closeCount());
    }

    @Test
    void defaultSessionFactoryRejectsAmbiguousSerialBeforeReturningASession() throws Exception {
        var driver = new TestTokenDriver("test", true);
        var request = request("1234".toCharArray(), file("one", "source.pdf", "signed.pdf"));
        var ambiguousRequest = new SignRequest("test", driver.serial(), request.pin(), request.signatureLevel(),
                request.timestamp(), request.files());
        var factory = new MachineSigningService.DefaultSessionFactory(() -> List.of(driver), new MachineSettings(true),
                PasswordManager::new);

        var failure = assertThrows(MachineProtocolException.class, () -> factory.apply(ambiguousRequest));

        assertEquals("CERTIFICATE_AMBIGUOUS", failure.getMessage());
        assertEquals(1, driver.closeCount());
    }

    @Test
    void failedPasswordManagerConstructionClosesAndZeroizesMachineSecretUi() {
        var capturedUi = new AtomicReference<MachineSecretUI>();
        var issuedSecret = new AtomicReference<char[]>();
        var request = new SignRequest("test", "123", "1234".toCharArray(), "PAdES_BASELINE_T",
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")), List.of());

        assertThrows(IllegalStateException.class, () -> MachineSigningService.DefaultSigningSession.open(
                new TestTokenDriver("test"), request, new MachineSettings(true), (ui, settings) -> {
                    capturedUi.set(ui);
                    issuedSecret.set(ui.getKeystorePassword());
                    throw new IllegalStateException("factory failure");
                }));

        assertTrue(capturedUi.get().isClosed());
        assertTrue(Arrays.equals(new char[issuedSecret.get().length], issuedSecret.get()));
    }

    @Test
    void errorDuringPasswordManagerConstructionStillZeroizesMachineSecretUi() {
        var capturedUi = new AtomicReference<MachineSecretUI>();
        var issuedSecret = new AtomicReference<char[]>();
        var request = new SignRequest("test", "123", "1234".toCharArray(), "PAdES_BASELINE_T",
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")), List.of());

        assertThrows(AssertionError.class, () -> MachineSigningService.DefaultSigningSession.open(
                new TestTokenDriver("test"), request, new MachineSettings(true), (ui, settings) -> {
                    capturedUi.set(ui);
                    issuedSecret.set(ui.getKeystorePassword());
                    throw new AssertionError("factory error");
                }));

        assertTrue(capturedUi.get().isClosed());
        assertTrue(Arrays.equals(new char[issuedSecret.get().length], issuedSecret.get()));
    }

    @Test
    void signingJobUsesTheRequiredPadesBaselineTPolicy() throws Exception {
        var source = Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample.pdf").getFile());
        var responder = new MachineFileResponder(target("policy-signed.pdf"), ignored -> { });
        var settings = new MachineSettings(true);
        settings.setTsaServer("https://tsa.example.test");
        settings.setTsaEnabled(true);

        var job = MachineSigningService.DefaultSigningSession.signingJob(source, responder, settings);

        assertEquals(SignatureLevel.PAdES_BASELINE_T, job.getParameters().getLevel());
        assertEquals(eu.europa.esig.dss.enumerations.SignatureForm.PAdES, job.getParameters().getSignatureType());
    }

    private SignRequest request(char[] pin, MachineFile... files) {
        return new SignRequest("fake", "123", pin, "PAdES_BASELINE_T",
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")), List.of(files));
    }

    private MachineFile file(String id, String sourceName, String targetName) throws Exception {
        var source = Files.writeString(temporaryDirectory.resolve(sourceName), "%PDF-1.7\nfixture\n%%EOF").toRealPath();
        return new MachineFile(id, source.toString(), target(targetName).toString());
    }

    private Path target(String name) throws Exception {
        return temporaryDirectory.toRealPath().resolve(name);
    }

    private static SimpleReport qualifiedReport(String... ids) {
        var report = mock(SimpleReport.class);
        when(report.getSignatureIdList()).thenReturn(List.of(ids));
        for (var id : ids) {
            var timestamp = new XmlTimestamp();
            timestamp.setId("ts-" + id);
            when(report.getSignatureFormat(id)).thenReturn(SignatureLevel.PAdES_BASELINE_T);
            when(report.isValid(id)).thenReturn(true);
            when(report.getIndication(id)).thenReturn(Indication.TOTAL_PASSED);
            when(report.getSignatureTimestamps(id)).thenReturn(List.of(timestamp));
            when(report.isValid("ts-" + id)).thenReturn(true);
            when(report.getTimestampQualification("ts-" + id)).thenReturn(
                    eu.europa.esig.dss.enumerations.TimestampQualification.QTSA);
        }
        return report;
    }

    private static final class TestTokenDriver extends TokenDriver {
        private final boolean duplicateKey;
        private TestToken token;
        private boolean created;

        private TestTokenDriver(String shortname) {
            this(shortname, false);
        }

        private TestTokenDriver(String shortname, boolean duplicateKey) {
            super("Test token", Path.of("test-token"), shortname, "");
            this.duplicateKey = duplicateKey;
        }

        @Override
        public AbstractKeyStoreTokenConnection createToken(PasswordManager passwordManager,
                digital.slovensko.autogram.core.SignatureTokenSettings settings) {
            created = true;
            try {
                token = new TestToken(duplicateKey);
                return token;
            } catch (java.io.IOException exception) {
                throw new IllegalStateException(exception);
            }
        }

        private String serial() throws Exception {
            if (token == null) {
                var preview = new TestToken(duplicateKey);
                try {
                    return preview.getKeys().getFirst().getCertificate().getSerialNumber().toString();
                } finally {
                    preview.close();
                }
            }
            return token.getKeys().getFirst().getCertificate().getSerialNumber().toString();
        }

        private int closeCount() {
            return token == null ? 0 : token.closeCount;
        }
    }

    private static final class TestToken extends Pkcs12SignatureToken {
        private final boolean duplicateKey;
        private int closeCount;

        private TestToken(boolean duplicateKey) throws java.io.IOException {
            super(MachineSigningServiceTest.class.getResource("/digital/slovensko/autogram/test.keystore").getFile(),
                    new KeyStore.PasswordProtection(new char[0]));
            this.duplicateKey = duplicateKey;
        }

        @Override
        public List<eu.europa.esig.dss.token.DSSPrivateKeyEntry> getKeys() {
            var keys = super.getKeys();
            return duplicateKey ? List.of(keys.getFirst(), keys.getFirst()) : keys;
        }

        @Override
        public void close() {
            closeCount++;
            super.close();
        }
    }

    private static final class FakeSession implements MachineSigningService.SigningSession {
        private final SignBehavior behavior;
        private final boolean closeFails;
        private boolean closed;

        private FakeSession(SignBehavior behavior) {
            this(behavior, false);
        }

        private FakeSession(SignBehavior behavior, boolean closeFails) {
            this.behavior = behavior;
            this.closeFails = closeFails;
        }

        @Override
        public void sign(MachineFile file, Runnable completed) throws Exception {
            behavior.sign(file, completed);
        }

        @Override
        public void close() {
            closed = true;
            if (closeFails) {
                throw new IllegalStateException("close failure");
            }
        }
    }

    @FunctionalInterface
    private interface SignBehavior {
        void sign(MachineFile file, Runnable completed) throws Exception;
    }

    private static final class RecordingWriter {
        private final StringWriter output = new StringWriter();

        private MachineEventWriter writer() {
            return new MachineEventWriter(new PrintWriter(output));
        }

        private List<String> eventTypes() {
            return events().stream().map(event -> event.get("type").getAsString()).toList();
        }

        private String payloadCode(int eventIndex) {
            return events().get(eventIndex).getAsJsonObject("payload").get("code").getAsString();
        }

        private String serialized() {
            return output.toString();
        }

        private List<com.google.gson.JsonObject> events() {
            return Arrays.stream(output.toString().strip().split("\\n"))
                    .map(JsonParser::parseString).map(value -> value.getAsJsonObject()).toList();
        }
    }
}
