package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class MachineRequestValidatorTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void rejectsBaselineBEvenWhenRequestedByCaller() throws Exception {
        var request = signRequest("PAdES_BASELINE_B", files(pdf("source.pdf"), target("signed.pdf")));

        var failure = assertThrows(MachineProtocolException.class,
                () -> MachineRequestValidator.validateSign(request));

        assertEquals("SIGNATURE_LEVEL_REQUIRED", failure.getMessage());
    }

    @Test
    void acceptsOnlyCanonicalAbsolutePdfSourceAndNewExplicitTarget() throws Exception {
        var request = signRequest("PAdES_BASELINE_T", files(pdf("source.pdf"), target("signed.pdf")));

        assertDoesNotThrow(() -> MachineRequestValidator.validateSign(request));
    }

    @Test
    void rejectsMissingAndExistingTargetFiles() throws Exception {
        var missing = signRequest("PAdES_BASELINE_T", files(temporaryDirectory.resolve("missing.pdf"), target("one.pdf")));
        var existingTarget = Files.writeString(target("existing.pdf"), "%PDF-1.7\n%%EOF");
        var collision = signRequest("PAdES_BASELINE_T", files(pdf("source.pdf"), existingTarget));

        assertInvalid(missing);
        assertInvalid(collision);
    }

    @Test
    void rejectsPathTraversalNonAbsoluteAndDuplicateTargets() throws Exception {
        var source = pdf("source.pdf");
        var traversal = signRequest("PAdES_BASELINE_T", files(source, temporaryDirectory.resolve("nested/../signed.pdf")));
        var relative = signRequest("PAdES_BASELINE_T", List.of(new MachineFile("one", "source.pdf", target("one.pdf").toString())));
        var relativeTarget = signRequest("PAdES_BASELINE_T", List.of(new MachineFile("one", source.toString(), "one.pdf")));
        var samePath = signRequest("PAdES_BASELINE_T", files(source, source));
        var malformed = signRequest("PAdES_BASELINE_T", List.of(new MachineFile("one", source.toString(), "\0.pdf")));
        var duplicate = signRequest("PAdES_BASELINE_T", List.of(
                new MachineFile("one", source.toString(), target("same.pdf").toString()),
                new MachineFile("two", pdf("other.pdf").toString(), target("same.pdf").toString())));

        assertInvalid(traversal);
        assertInvalid(relative);
        assertInvalid(relativeTarget);
        assertInvalid(samePath);
        assertInvalid(malformed);
        assertInvalid(duplicate);
    }

    @Test
    void rejectsCaseInsensitiveDuplicateTargetsBeforeTokenWork() throws Exception {
        var source = pdf("source.pdf");
        var duplicate = signRequest("PAdES_BASELINE_T", List.of(
                new MachineFile("one", source.toString(), target("Signed.PDF").toString()),
                new MachineFile("two", pdf("other.pdf").toString(), target("signed.pdf").toString())));

        assertInvalid(duplicate);
    }

    @Test
    void rejectsUnicodeEquivalentDuplicateTargetsBeforeTokenWork() throws Exception {
        var source = pdf("source.pdf");
        var composed = target("podpis-é.pdf");
        var decomposed = target("podpis-e\u0301.pdf");
        var duplicate = signRequest("PAdES_BASELINE_T", List.of(
                new MachineFile("one", source.toString(), composed.toString()),
                new MachineFile("two", pdf("other.pdf").toString(), decomposed.toString())));

        assertInvalid(duplicate);
    }

    @Test
    void rejectsASymlinkedSourceBeforeAnyTokenWork() throws Exception {
        var source = pdf("source.pdf");
        var link = temporaryDirectory.resolve("source-link.pdf");
        Files.createSymbolicLink(link, source);

        assertInvalid(signRequest("PAdES_BASELINE_T", files(link, target("signed.pdf"))));
    }

    @Test
    void requiresQualifiedTimestampAndSupportedTsaUrl() throws Exception {
        var source = pdf("source.pdf");
        var timestampNotRequired = request(source, target("not-required.pdf"), false, List.of("https://tsa.example.test"));
        var unsupportedTsa = request(source, target("unsupported.pdf"), true, List.of("file:///tsa"));

        assertEquals("TIMESTAMP_REQUIRED", failureCode(timestampNotRequired));
        assertEquals("TSA_REQUIRED", failureCode(unsupportedTsa));
    }

    private SignRequest request(Path source, Path target, boolean required, List<String> servers) {
        return new SignRequest("fake", "123", "1234".toCharArray(), "PAdES_BASELINE_T",
                new QualifiedTimestampRequest(required, servers), files(source, target));
    }

    private SignRequest signRequest(String signatureLevel, List<MachineFile> files) {
        return new SignRequest("fake", "123", "1234".toCharArray(), signatureLevel,
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")), files);
    }

    private List<MachineFile> files(Path source, Path target) {
        return List.of(new MachineFile("one", source.toString(), target.toString()));
    }

    private Path pdf(String name) throws IOException {
        return Files.writeString(temporaryDirectory.resolve(name), "%PDF-1.7\nfixture\n%%EOF").toRealPath();
    }

    private Path target(String name) throws IOException {
        return temporaryDirectory.toRealPath().resolve(name);
    }

    private static void assertInvalid(SignRequest request) {
        assertEquals("PROTOCOL_INVALID_REQUEST", failureCode(request));
    }

    private static String failureCode(SignRequest request) {
        return assertThrows(MachineProtocolException.class, () -> MachineRequestValidator.validateSign(request)).getMessage();
    }
}
