package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonParser;
import digital.slovensko.autogram.core.SignedDocument;
import eu.europa.esig.dss.model.InMemoryDocument;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
    void completionCallbackFailureDeletesOnlyTheReservedTarget() throws Exception {
        var target = target("callback-failed.pdf");
        var responder = new MachineFileResponder(target, ignored -> {
            throw new IllegalStateException("callback failure");
        });

        assertThrows(MachineProtocolException.class,
                () -> responder.onDocumentSigned(new SignedDocument(new InMemoryDocument("replacement".getBytes()), null)));

        assertFalse(Files.exists(target));
    }

    @Test
    void signingFailureNeverDeletesATargetCreatedAfterValidation() throws Exception {
        var writer = new RecordingWriter();
        var target = target("late-collision.pdf");
        var service = new MachineSigningService(writer.writer(), request -> new FakeSession((file, completed) -> {
            Files.writeString(Path.of(file.target()), "%PDF-1.7\nother process\n%%EOF");
            throw new IllegalStateException("late collision");
        }), path -> true);

        service.sign("request-1", request("1234".toCharArray(), file("one", "source.pdf", target.getFileName().toString())));

        assertEquals("%PDF-1.7\nother process\n%%EOF", Files.readString(target));
        assertEquals("SIGNING_FAILED", writer.payloadCode(2));
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
