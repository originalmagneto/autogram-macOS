package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonParser;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.core.SignedDocument;
import digital.slovensko.autogram.core.errors.PINIncorrectException;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.machine.v2.VisibleSignatureAppearance;
import eu.europa.esig.dss.enumerations.ASiCContainerType;
import eu.europa.esig.dss.enumerations.Indication;
import eu.europa.esig.dss.enumerations.SignatureForm;
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
import java.time.Instant;
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
    void uncheckedCleanupFailureClearsPinAndEmitsNoDuplicateTerminalEvents() throws Exception {
        var writer = new RecordingWriter();
        var pin = "1234".toCharArray();
        var fileSystem = new TrackingFileSystem();
        fileSystem.cleanupFailure = new AssertionError("unchecked cleanup detail");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((input, completed) -> {
            input.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
            completed.run();
        }), content -> true, () -> { }, fileSystem);

        service.sign("request-1", request(pin, file("one", "source.pdf", "cleanup-error.pdf")));

        assertTrue(Arrays.equals(new char[pin.length], pin));
        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.failed"),
                writer.lifecycleEventTypes());
        assertEquals("OUTPUT_CLEANUP_FAILED", writer.payloadCode(3));
        assertFalse(writer.serialized().contains("unchecked cleanup detail"));
    }

    @Test
    void continuesAfterOneFileFails() throws Exception {
        var writer = new RecordingWriter();
        var session = new FakeSession((file, completed) -> {
            if (file.file().id().equals("bad")) {
                throw new IllegalStateException("sensitive failure");
            }
            file.writeSignedContent("%PDF-1.7\ngood\n%%EOF".getBytes());
            completed.run();
        });
        var service = new MachineSigningService(writer.writer(), request -> session, path -> true);
        var pin = "1234".toCharArray();

        service.sign("request-1", request(pin, file("bad", "bad.pdf", "bad-signed.pdf"),
                file("good", "good.pdf", "good-signed.pdf")));

        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "file.signingStarted",
                "file.completed", "session.completed"), writer.lifecycleEventTypes());
        assertTrue(session.closed);
        assertTrue(Arrays.equals(new char[pin.length], pin));
        assertFalse(writer.serialized().contains("sensitive failure"));
    }

    @Test
    void emitsProgressAtMachineSigningBoundaries() throws Exception {
        var writer = new RecordingWriter();
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            file.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
            completed.run();
        }), path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "signed.pdf")));

        assertEquals(List.of("preparing", "signing", "validating", "saving"), writer.progressPhases());
    }

    @Test
    void v1SigningDoesNotInitializeTrustedLists() throws Exception {
        var writer = new RecordingWriter();
        var target = target("signed.pdf");
        var trustInitialized = new AtomicBoolean();
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            file.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
            completed.run();
        }), content -> true, () -> trustInitialized.set(true));

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertFalse(trustInitialized.get());
        assertTrue(Files.exists(target));
        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.completed"),
                writer.lifecycleEventTypes());
    }

    @Test
    void visibleSigningRequiresTrustedListsBeforeTokenWork() throws Exception {
        var writer = new RecordingWriter();
        var target = target("visible-signed.pdf");
        var sessionOpened = new AtomicBoolean();
        var service = new MachineSigningService(writer.writer(), request -> {
            sessionOpened.set(true);
            throw new AssertionError("Token work must not start without trusted lists");
        }, content -> true, () -> { throw new MachineProtocolException("TRUSTED_LIST_UNAVAILABLE"); });

        service.sign("request-1", request("1234".toCharArray(),
                visibleFile("one", "visible-source.pdf", target.getFileName().toString())));

        assertFalse(sessionOpened.get());
        assertFalse(Files.exists(target));
        assertEquals("TRUSTED_LIST_UNAVAILABLE", writer.payloadCode(2));
    }

    @Test
    void deletesInvalidOutputBeforeReportingOutputValidationFailure() throws Exception {
        var writer = new RecordingWriter();
        var target = target("invalid-signed.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            file.writeSignedContent("%PDF-1.7\ninvalid\n%%EOF".getBytes());
            completed.run();
        }), path -> false);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertFalse(Files.exists(target));
        assertEquals("OUTPUT_VALIDATION_FAILED", writer.payloadCode(2));
        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "session.completed"),
                writer.lifecycleEventTypes());
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
                "file.failed", "session.failed"), writer.lifecycleEventTypes());
        assertTrue(Arrays.equals(new char[pin.length], pin));
        assertFalse(writer.serialized().contains("/private/card"));
        assertFalse(writer.serialized().contains("1234"));
    }

    @Test
    void reportsNestedIncorrectPinAsAStableFailureCode() throws Exception {
        var writer = new RecordingWriter();
        var service = new MachineSigningService(writer.writer(), request -> {
            throw new IllegalStateException(new PINIncorrectException());
        }, path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "one.pdf", "one-signed.pdf")));

        assertEquals("PIN_INCORRECT", writer.payloadCode(2));
    }

    @Test
    void emitsNoDuplicateFileEventsWhenSessionCloseFails() throws Exception {
        var writer = new RecordingWriter();
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            file.writeSignedContent("%PDF-1.7\ngood\n%%EOF".getBytes());
            completed.run();
        }, true), path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "signed.pdf")));

        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.failed"),
                writer.lifecycleEventTypes());
    }

    @Test
    void responderWritesOnlyThroughTheRetainedStagingHandle() {
        var target = new MemoryRetainedFile();
        var responder = new MachineFileResponder(target, () -> { });

        responder.onDocumentSigned(new SignedDocument(new InMemoryDocument("replacement".getBytes()), null));

        assertEquals("replacement", new String(target.content));
    }

    @Test
    void completionCallbackFailureLeavesThePrivateOwnerToCleanItsTarget() throws Exception {
        var target = new MemoryRetainedFile();
        var responder = new MachineFileResponder(target, () -> {
            throw new IllegalStateException("callback failure");
        });

        assertThrows(MachineProtocolException.class,
                () -> responder.onDocumentSigned(new SignedDocument(new InMemoryDocument("replacement".getBytes()), null)));

        assertEquals("replacement", new String(target.content));
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
        var service = new MachineSigningService(writer.writer(), request -> {
            try {
                assertEquals("%PDF-1.7\noriginal\n%%EOF", Files.readString(source));
                Files.writeString(source, "%PDF-1.7\nreplaced\n%%EOF", StandardOpenOption.TRUNCATE_EXISTING);
            } catch (java.io.IOException exception) {
                throw new IllegalStateException(exception);
            }
            sessionOpened.set(true);
            return new FakeSession((file, completed) -> {
                sourceSeenBySigner.set(new String(file.sourceContent()));
                file.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
                completed.run();
            });
        }, path -> true);

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
            file.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
            completed.run();
        }), new MachineSigningService.PdfOutputValidator(inspection));

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertFalse(targetSeenDuringSigning.get());
        assertEquals("%PDF-1.7\nsigned\n%%EOF", Files.readString(target));
        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.completed"),
                writer.lifecycleEventTypes());
    }

    @Test
    void validationFailureNeverDeletesAConcurrentUserTargetReplacement() throws Exception {
        var writer = new RecordingWriter();
        var target = target("concurrent-user-target.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            file.writeSignedContent("%PDF-1.7\ninvalid\n%%EOF".getBytes());
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
            file.writeSignedContent("%PDF-1.7\ninvalid\n%%EOF".getBytes());
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
            file.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
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
        var nativeFiles = MacNativeFileSystem.createForCurrentPlatform();
        var service = new MachineSigningService(writer.writer(), request -> {
            tokenOpened.set(true);
            throw new AssertionError("Token must not open after preparation cleanup failure");
        }, content -> true, () -> { }, new MachineSigningFileSystem() {
            @Override
            public RetainedFile openSource(Path source) throws java.io.IOException {
                return nativeFiles.openSource(source);
            }

            @Override
            public Workspace createWorkspace(Path targetParent) {
                return failingWorkspace(false);
            }
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "target.pdf")));

        assertFalse(tokenOpened.get());
        assertEquals(List.of("session.started", "file.signingStarted", "file.failed", "session.failed"),
                writer.lifecycleEventTypes());
        assertEquals("OUTPUT_CLEANUP_FAILED", writer.payloadCode(2));
    }

    @Test
    void identitySetupFailureCleansThePreparedSourceBeforeTokenWork() throws Exception {
        var writer = new RecordingWriter();
        var tokenOpened = new AtomicBoolean();
        var sourceClosed = new AtomicBoolean();
        var service = new MachineSigningService(writer.writer(), request -> {
            tokenOpened.set(true);
            throw new AssertionError("Token must not open after source setup failure");
        }, content -> true, () -> { }, new MachineSigningFileSystem() {
            @Override
            public RetainedFile openSource(Path source) {
                return new MemoryRetainedFile("%PDF-1.7\nsource\n%%EOF".getBytes()) {
                    @Override
                    public void close() {
                        sourceClosed.set(true);
                    }
                };
            }

            @Override
            public Workspace createWorkspace(Path targetParent) {
                throw new IllegalStateException("identity capture failed");
            }
        });

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", "target.pdf")));

        assertFalse(tokenOpened.get());
        assertTrue(sourceClosed.get());
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
    void unavailableTimestampQualificationPreventsPublication() throws Exception {
        var writer = new RecordingWriter();
        var target = target("timestamp-unqualified.pdf");
        var inspection = new MachineInspectionService(path -> locallyValidTimestampReport("existing"), content ->
                new String(content, java.nio.charset.StandardCharsets.ISO_8859_1).contains("signed")
                        ? locallyValidTimestampReport("existing", "new") : locallyValidTimestampReport("existing"));
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            file.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
            completed.run();
        }), new MachineSigningService.PdfOutputValidator(inspection));

        service.sign("request-1", request("1234".toCharArray(),
                visibleFile("one", "source.pdf", target.getFileName().toString())));

        assertFalse(Files.exists(target));
        assertEquals("TIMESTAMP_QUALIFICATION_FAILED", writer.payloadCode(2));
    }

    @Test
    void productionTrustedInspectionAllowsQualifiedVisiblePadesPublication() {
        var inspection = MachineInspectionService.forTrustedValidation(ignored -> qualifiedReport("new"));
        var validator = new MachineSigningService.PdfOutputValidator(inspection);
        var output = "%PDF-1.7\nvalidated\n%%EOF".getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);

        assertEquals(null, validator.validationFailure(output, java.util.Set.of(), true));
    }

    @Test
    void visiblePublicationRequiresPadesWhileV1KeepsBaselineTFormats() {
        var report = qualifiedReport("new");
        when(report.getSignatureFormat("new")).thenReturn(SignatureLevel.XAdES_BASELINE_T);
        var validator = new MachineSigningService.PdfOutputValidator(new MachineInspectionService(path -> report,
                content -> report));
        var output = "%PDF-1.7\nvalidated\n%%EOF".getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);

        assertEquals("OUTPUT_VALIDATION_FAILED", validator.validationFailure(output, java.util.Set.of(), true));
        assertEquals(null, validator.validationFailure(output, java.util.Set.of(), false));
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
        var responder = new MachineFileResponder(new MemoryRetainedFile(), () -> { });
        var settings = new MachineSettings(true);
        settings.setTsaServer("https://tsa.example.test");
        settings.setTsaEnabled(true);

        var job = MachineSigningService.DefaultSigningSession.signingJob(Files.readAllBytes(source), source.toString(),
                responder, settings);

        assertEquals(SignatureLevel.PAdES_BASELINE_T, job.getParameters().getLevel());
        assertEquals(eu.europa.esig.dss.enumerations.SignatureForm.PAdES, job.getParameters().getSignatureType());
    }

    @Test
    void signingJobBindsTheSnapshottedVisiblePadesAppearance() throws Exception {
        var source = Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample.pdf").getFile());
        var image = temporaryDirectory.resolve("visible-signature.png");
        Files.copy(Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample.png").getFile()), image);
        var appearance = new VisibleSignatureAppearance(image.toString(), 2, 72, 540, 216, 108,
                Instant.parse("2026-08-10T12:34:56Z"));
        var snapshot = appearance.snapshot();
        Files.writeString(image, "replacement");
        var responder = new MachineFileResponder(new MemoryRetainedFile(), () -> { });
        var settings = new MachineSettings(true);
        settings.setTsaServer("https://tsa.example.test");
        settings.setTsaEnabled(true);

        var job = MachineSigningService.DefaultSigningSession.signingJob(Files.readAllBytes(source), source.toString(),
                responder, settings, snapshot);
        var parameters = job.getParameters().getPAdESSignatureParameters();
        var field = parameters.getImageParameters().getFieldParameters();

        assertEquals(2, field.getPage());
        assertEquals(72, field.getOriginX());
        assertEquals(540, field.getOriginY());
        assertEquals(216, field.getWidth());
        assertEquals(108, field.getHeight());
        assertEquals(eu.europa.esig.dss.enumerations.VisualSignatureRotation.NONE, field.getRotation());
        assertEquals(eu.europa.esig.dss.enumerations.ImageScaling.STRETCH,
                parameters.getImageParameters().getImageScaling());
        assertEquals(Instant.parse("2026-08-10T12:34:56Z"), parameters.getSigningDate().toInstant());
        try (var imageStream = parameters.getImageParameters().getImage().openStream()) {
            assertTrue(Arrays.equals(snapshot.pngBytes(), imageStream.readAllBytes()));
        }
    }

    @Test
    void signingJobWrapsPdfInAsicEWithXadesWhenRequested() throws Exception {
        var source = Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample.pdf").getFile());
        var responder = new MachineFileResponder(new MemoryRetainedFile(), () -> { });
        var settings = new MachineSettings(true);
        settings.setSignatureLevel(SignatureLevel.XAdES_BASELINE_T);
        settings.setTsaServer("https://tsa.example.test");
        settings.setTsaEnabled(true);

        var job = MachineSigningService.DefaultSigningSession.signingJob(Files.readAllBytes(source), source.toString(),
                responder, settings);

        assertEquals(SignatureLevel.XAdES_BASELINE_T, job.getParameters().getLevel());
        assertEquals(SignatureForm.XAdES, job.getParameters().getSignatureType());
        assertEquals(ASiCContainerType.ASiC_E, job.getParameters().getContainer());
    }

    @Test
    void signingJobUsesTheExistingAsicXadesFormatAndQualifiedTimestampPolicy() throws Exception {
        var source = Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample_pdf_xades.asice").getFile());
        var responder = new MachineFileResponder(new MemoryRetainedFile(), () -> { });
        var settings = new MachineSettings(true);
        settings.setTsaServer("https://tsa.example.test");
        settings.setTsaEnabled(true);

        var job = MachineSigningService.DefaultSigningSession.signingJob(Files.readAllBytes(source), source.toString(),
                responder, settings);

        assertEquals(SignatureLevel.XAdES_BASELINE_T, job.getParameters().getLevel());
        assertEquals(eu.europa.esig.dss.enumerations.SignatureForm.XAdES, job.getParameters().getSignatureType());
    }

    @Test
    void configuresBasicTimestampAuthenticationForOnlyTheRequestedHostsAndClearsTheReceivedSecret() {
        var receivedSecret = "timestamp-password".toCharArray();
        var request = new QualifiedTimestampRequest(true,
                List.of("https://first.tsa.example.test", "https://second.tsa.example.test:8443"),
                new TimestampAuthentication("basic", "timestamp-user", receivedSecret));

        var dataLoader = MachineSigningService.MachineTimestampDataLoader.create(request);
        request.clearAuthentication();

        assertEquals(2, dataLoader.getAuthenticationMap().size());
        assertTrue(dataLoader.getAuthenticationMap().keySet().stream()
                .allMatch(host -> host.getHost().endsWith(".tsa.example.test")));
        assertTrue(Arrays.equals(new char[receivedSecret.length], receivedSecret));

        dataLoader.clearAuthentication();
        assertTrue(dataLoader.getAuthenticationMap().values().stream()
                .allMatch(credentials -> Arrays.equals(new char[credentials.getPassword().length], credentials.getPassword())));
    }

    private SignRequest request(char[] pin, MachineFile... files) {
        return new SignRequest("fake", "123", pin, "PAdES_BASELINE_T",
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")), List.of(files));
    }

    private MachineFile file(String id, String sourceName, String targetName) throws Exception {
        var source = Files.writeString(temporaryDirectory.resolve(sourceName), "%PDF-1.7\nfixture\n%%EOF").toRealPath();
        return new MachineFile(id, source.toString(), target(targetName).toString());
    }

    private MachineFile visibleFile(String id, String sourceName, String targetName) throws Exception {
        var file = file(id, sourceName, targetName);
        var image = temporaryDirectory.resolve(id + "-visible.png");
        Files.copy(Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample.png").getFile()), image);
        var appearance = new VisibleSignatureAppearance(image.toString(), 2, 72, 540, 216, 108,
                Instant.parse("2026-08-10T12:34:56Z")).snapshot();
        return new MachineFile(file.id(), file.source(), file.target(), appearance);
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

    private static SimpleReport locallyValidTimestampReport(String... ids) {
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

    private static MachineSigningFileSystem.Workspace failingWorkspace(boolean cleanupResult) {
        return new MachineSigningFileSystem.Workspace() {
            @Override
            public MachineSigningFileSystem.RetainedFile createStagingFile() throws java.io.IOException {
                throw new java.io.IOException("identity capture failed");
            }

            @Override
            public void publish(MachineSigningFileSystem.RetainedFile source, String targetLeaf) {
                throw new AssertionError("Publication must not run");
            }

            @Override
            public boolean cleanup() {
                return cleanupResult;
            }

            @Override
            public void close() {
            }
        };
    }

    private static class MemoryRetainedFile implements MachineSigningFileSystem.RetainedFile {
        private byte[] content;

        private MemoryRetainedFile() {
            this(new byte[0]);
        }

        private MemoryRetainedFile(byte[] content) {
            this.content = content.clone();
        }

        @Override
        public byte[] readAll() {
            return content.clone();
        }

        @Override
        public void replaceContent(byte[] content) {
            this.content = content.clone();
        }

        @Override
        public void close() {
        }
    }

    private static final class TrackingFileSystem implements MachineSigningFileSystem {
        private final MemoryRetainedFile source = new MemoryRetainedFile("%PDF-1.7\nsource\n%%EOF".getBytes());
        private final MemoryRetainedFile staging = new MemoryRetainedFile();
        private Error cleanupFailure;

        @Override
        public RetainedFile openSource(Path source) {
            return this.source;
        }

        @Override
        public Workspace createWorkspace(Path targetParent) {
            return new Workspace() {
                @Override
                public RetainedFile createStagingFile() {
                    return staging;
                }

                @Override
                public void publish(RetainedFile source, String targetLeaf) throws java.io.IOException {
                }

                @Override
                public boolean cleanup() {
                    if (cleanupFailure != null) {
                        throw cleanupFailure;
                    }
                    return true;
                }

                @Override
                public void close() {
                }
            };
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
        public void sign(MachineSigningService.SigningInput input, Runnable completed) throws Exception {
            behavior.sign(input, completed);
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
        void sign(MachineSigningService.SigningInput file, Runnable completed) throws Exception;
    }

    private static final class RecordingWriter {
        private final StringWriter output = new StringWriter();

        private MachineEventWriter writer() {
            return new MachineEventWriter(new PrintWriter(output));
        }

        private List<String> lifecycleEventTypes() {
            return events().stream()
                    .filter(event -> !"file.progress".equals(event.get("type").getAsString()))
                    .map(event -> event.get("type").getAsString()).toList();
        }

        private List<String> progressPhases() {
            return events().stream()
                    .filter(event -> "file.progress".equals(event.get("type").getAsString()))
                    .map(event -> event.getAsJsonObject("payload").get("phase").getAsString()).toList();
        }

        private String payloadCode(int eventIndex) {
            return events().stream()
                    .filter(event -> !"file.progress".equals(event.get("type").getAsString()))
                    .toList().get(eventIndex).getAsJsonObject("payload").get("code").getAsString();
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
