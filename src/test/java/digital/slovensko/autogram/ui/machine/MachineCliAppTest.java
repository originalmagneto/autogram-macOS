package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonParser;
import eu.europa.esig.dss.enumerations.Indication;
import eu.europa.esig.dss.enumerations.SignatureLevel;
import eu.europa.esig.dss.simplereport.SimpleReport;
import eu.europa.esig.dss.simplereport.jaxb.XmlTimestamp;
import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.Options;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.PrintWriter;
import java.io.Reader;
import java.io.StringReader;
import java.io.StringWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class MachineCliAppTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void rejectsUnsupportedProtocolVersionAsJsonEvent() throws Exception {
        var stdin = new StringReader("{\"protocolVersion\":2,\"requestId\":\"r\",\"operation\":\"CAPABILITIES\",\"payload\":{}}");
        var stdout = new StringWriter();

        var code = MachineCliApp.start(commandLine("CAPABILITIES"), stdin, new PrintWriter(stdout),
                new PrintWriter(new StringWriter()));

        assertEquals(64, code);
        assertTrue(stdout.toString().contains("PROTOCOL_UNSUPPORTED_VERSION"));
        var event = JsonParser.parseString(stdout.toString()).getAsJsonObject();
        assertEquals("session.failed", event.get("type").getAsString());
        assertEquals("PROTOCOL_UNSUPPORTED_VERSION", event.getAsJsonObject("payload").get("code").getAsString());
    }

    @Test
    void rejectsOperationDifferentFromCommandLineAsJsonEvent() throws Exception {
        var stdout = new StringWriter();

        var code = MachineCliApp.start(commandLine("SIGN"),
                new StringReader("{\"protocolVersion\":1,\"requestId\":\"r\",\"operation\":\"CAPABILITIES\",\"payload\":{}}"),
                new PrintWriter(stdout), new PrintWriter(new StringWriter()));

        assertEquals(64, code);
        assertEquals("OPERATION_MISMATCH",
                JsonParser.parseString(stdout.toString()).getAsJsonObject().getAsJsonObject("payload").get("code").getAsString());
    }

    @Test
    void rejectsMissingProtocolVersionWithoutReadingStandardInput() throws Exception {
        var stdout = new StringWriter();
        var unreadableInput = new Reader() {
            @Override
            public int read(char[] buffer, int offset, int length) {
                throw new AssertionError("standard input must not be read");
            }

            @Override
            public void close() {
            }
        };

        var code = MachineCliApp.start(commandLineWithoutProtocolVersion(), unreadableInput, new PrintWriter(stdout),
                new PrintWriter(new StringWriter()));

        assertEquals(64, code);
        assertEquals("PROTOCOL_INVALID_REQUEST",
                JsonParser.parseString(stdout.toString()).getAsJsonObject().getAsJsonObject("payload").get("code").getAsString());
    }

    @Test
    void dispatchesCapabilitiesWithRequiredTimestampPolicy() throws Exception {
        var events = start("CAPABILITIES", "{}", serviceWith());

        assertEquals(List.of("session.started", "session.completed"), eventTypes(events));
        assertTrue(events.get(1).getAsJsonObject("payload").getAsJsonObject("timestampPolicy")
                .get("required").getAsBoolean());
    }

    @Test
    void dispatchesDriversWithDriverMetadata() throws Exception {
        var events = start("DRIVERS", "{}", serviceWith(new InstalledTestDriver("fake")));

        assertEquals(List.of("session.started", "driver.detected", "session.completed"), eventTypes(events));
        var driver = events.get(1).getAsJsonObject("payload").getAsJsonArray("drivers").get(0).getAsJsonObject();
        assertEquals("fake", driver.get("id").getAsString());
        assertEquals("Installed test driver", driver.get("name").getAsString());
        assertEquals("/installed/test-driver", driver.get("path").getAsString());
        assertTrue(driver.get("installed").getAsBoolean());
    }

    @Test
    void dispatchesCertificatesWithCertificatePayload() throws Exception {
        var events = start("CERTIFICATES", "{\"driver\":\"fake\",\"pin\":\"1234\"}",
                serviceWith(new digital.slovensko.autogram.drivers.FakeTokenDriver("Driver", Path.of("driver"), "fake", "")));

        assertEquals(List.of("session.started", "certificates.available", "session.completed"), eventTypes(events));
        var certificate = events.get(1).getAsJsonObject("payload").getAsJsonArray("certificates").get(0).getAsJsonObject();
        assertTrue(certificate.has("serial"));
        assertTrue(certificate.has("commonName"));
        assertTrue(certificate.has("validFrom"));
        assertTrue(certificate.has("validUntil"));
        assertTrue(certificate.has("expired"));
    }

    @Test
    void dispatchesCertificatesOnlyForExactDriverId() throws Exception {
        var driver = new InstalledTestDriver("fake");
        var events = startFailure("CERTIFICATES", "{\"driver\":\"FAKE\",\"pin\":\"1234\"}", serviceWith(driver), 69);

        assertEquals(List.of("session.started", "session.failed"), eventTypes(events));
        assertEquals("DRIVER_NOT_FOUND", events.get(1).getAsJsonObject("payload").get("code").getAsString());

        var exactEvents = start("CERTIFICATES", "{\"driver\":\"fake\",\"pin\":\"1234\"}", serviceWith(driver));
        assertEquals(List.of("session.started", "certificates.available", "session.completed"), eventTypes(exactEvents));
    }

    @Test
    void redactsPinAndDriverPathWhenCertificateReadFails() throws Exception {
        var events = startFailure("CERTIFICATES", "{\"driver\":\"broken\",\"pin\":\"1234\"}",
                serviceWith(new BrokenDriver()), 69);

        assertEquals(List.of("session.started", "session.failed"), eventTypes(events));
        assertEquals("DRIVER_UNAVAILABLE", events.get(1).getAsJsonObject("payload").get("code").getAsString());
        var serialized = events.toString();
        assertFalse(serialized.contains("1234"));
        assertFalse(serialized.contains("/sensitive/driver-path"));
    }

    @Test
    void dispatchesSuccessfulSignThroughHardwareFreeSigningServiceFactory() throws Exception {
        var source = Files.writeString(temporaryDirectory.resolve("source.pdf"), "%PDF-1.7\nsource\n%%EOF").toRealPath();
        var target = temporaryDirectory.toRealPath().resolve("signed.pdf");
        var stdout = new StringWriter();
        var input = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"SIGN\",\"payload\":{"
                + "\"driver\":\"fake\",\"certificateSerial\":\"123\",\"pin\":\"1234\","
                + "\"signatureLevel\":\"PAdES_BASELINE_T\",\"timestamp\":{\"required\":true,"
                + "\"servers\":[\"https://tsa.example.test\"]},\"files\":[{\"id\":\"one\",\"source\":\""
                + source + "\",\"target\":\"" + target + "\"}]}}";
        var inspection = new MachineInspectionService(path -> { throw new AssertionError("not used"); }, content ->
                new String(content).contains("signed") ? qualifiedReport("new") : qualifiedReport());
        var signingFactory = (MachineCliApp.SigningServiceFactory) (writer, ignoredInspection, ignoredTrust) ->
                new MachineSigningService(writer, request -> new MachineSigningService.SigningSession() {
                    @Override
                    public void sign(MachineSigningService.SigningInput input, Runnable completed) throws Exception {
                        input.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
                        completed.run();
                    }

                    @Override
                    public void close() {
                    }
                }, new MachineSigningService.PdfOutputValidator(ignoredInspection), ignoredTrust);

        var code = MachineCliApp.start(commandLine("SIGN"), new StringReader(input), new PrintWriter(stdout),
                new PrintWriter(new StringWriter()), new MachineDriverService(), inspection, () -> { }, signingFactory);

        var events = Arrays.stream(stdout.toString().strip().split("\\n"))
                .map(JsonParser::parseString).map(element -> element.getAsJsonObject()).toList();
        assertEquals(0, code, stdout.toString());
        assertEquals("%PDF-1.7\nsigned\n%%EOF", Files.readString(target));
        assertEquals(List.of("session.started", "file.signingStarted", "file.completed", "session.completed"),
                eventTypes(events));
    }

    @Test
    void acceptsOptionalTimestampAuthenticationWithoutRejectingTheSignRequest() throws Exception {
        var source = Files.writeString(temporaryDirectory.resolve("authenticated-source.pdf"), "%PDF-1.7\nsource\n%%EOF")
                .toRealPath();
        var target = temporaryDirectory.toRealPath().resolve("authenticated-signed.pdf");
        var stdout = new StringWriter();
        var input = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"SIGN\",\"payload\":{"
                + "\"driver\":\"fake\",\"certificateSerial\":\"123\",\"pin\":\"1234\","
                + "\"signatureLevel\":\"PAdES_BASELINE_T\",\"timestamp\":{\"required\":true,"
                + "\"servers\":[\"https://tsa.example.test\"],\"authentication\":{\"type\":\"basic\","
                + "\"username\":\"timestamp-user\",\"password\":\"timestamp-password\"}},\"files\":[{\"id\":\"one\",\"source\":\""
                + source + "\",\"target\":\"" + target + "\"}]}}";
        var inspection = new MachineInspectionService(path -> { throw new AssertionError("not used"); }, content ->
                new String(content).contains("signed") ? qualifiedReport("new") : qualifiedReport());
        var signingFactory = (MachineCliApp.SigningServiceFactory) (writer, ignoredInspection, ignoredTrust) ->
                new MachineSigningService(writer, request -> new MachineSigningService.SigningSession() {
                    @Override
                    public void sign(MachineSigningService.SigningInput input, Runnable completed) throws Exception {
                        input.writeSignedContent("%PDF-1.7\nsigned\n%%EOF".getBytes());
                        completed.run();
                    }

                    @Override
                    public void close() {
                    }
                }, new MachineSigningService.PdfOutputValidator(ignoredInspection), ignoredTrust);

        var code = MachineCliApp.start(commandLine("SIGN"), new StringReader(input), new PrintWriter(stdout),
                new PrintWriter(new StringWriter()), new MachineDriverService(), inspection, () -> { }, signingFactory);

        assertEquals(0, code, stdout.toString());
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

    private static CommandLine commandLine(String operation) throws Exception {
        var options = new Options()
                .addOption(null, "machine-readable", false, "")
                .addOption(null, "protocol-version", true, "")
                .addOption(null, "operation", true, "");
        return new DefaultParser().parse(options,
                new String[] { "--machine-readable", "--protocol-version", "1", "--operation", operation });
    }

    private static CommandLine commandLineWithoutProtocolVersion() throws Exception {
        var options = new Options()
                .addOption(null, "machine-readable", false, "")
                .addOption(null, "protocol-version", true, "")
                .addOption(null, "operation", true, "");
        return new DefaultParser().parse(options, new String[] { "--machine-readable", "--operation", "CAPABILITIES" });
    }

    private static List<com.google.gson.JsonObject> start(String operation, String payload, MachineDriverService service)
            throws Exception {
        return start(operation, payload, service, 0);
    }

    private static List<com.google.gson.JsonObject> startFailure(String operation, String payload,
            MachineDriverService service) throws Exception {
        return startFailure(operation, payload, service, 64);
    }

    private static List<com.google.gson.JsonObject> startFailure(String operation, String payload,
            MachineDriverService service, int expectedCode) throws Exception {
        return start(operation, payload, service, expectedCode);
    }

    private static List<com.google.gson.JsonObject> start(String operation, String payload, MachineDriverService service,
            int expectedCode) throws Exception {
        var stdout = new StringWriter();
        var input = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"" + operation
                + "\",\"payload\":" + payload + "}";

        assertEquals(expectedCode, MachineCliApp.start(commandLine(operation), new StringReader(input), new PrintWriter(stdout),
                new PrintWriter(new StringWriter()), service));

        return Arrays.stream(stdout.toString().strip().split("\\n"))
                .map(JsonParser::parseString).map(element -> element.getAsJsonObject()).toList();
    }

    private static List<String> eventTypes(List<com.google.gson.JsonObject> events) {
        return events.stream().map(event -> event.get("type").getAsString()).toList();
    }

    private static MachineDriverService serviceWith(digital.slovensko.autogram.drivers.TokenDriver... drivers) {
        return new MachineDriverService(() -> List.of(drivers), new MachineSettings());
    }

    private static final class BrokenDriver extends digital.slovensko.autogram.drivers.TokenDriver {
        private BrokenDriver() {
            super("Broken", Path.of("/sensitive/driver-path"), "broken", "");
        }

        @Override
        public eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection createToken(
                digital.slovensko.autogram.core.PasswordManager passwordManager,
                digital.slovensko.autogram.core.SignatureTokenSettings settings) {
            throw new RuntimeException("/sensitive/driver-path 1234");
        }
    }

    private static final class InstalledTestDriver extends digital.slovensko.autogram.drivers.TokenDriver {
        private InstalledTestDriver(String shortname) {
            super("Installed test driver", Path.of("/installed/test-driver"), shortname, "");
        }

        @Override
        public boolean isInstalled() {
            return true;
        }

        @Override
        public eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection createToken(
                digital.slovensko.autogram.core.PasswordManager passwordManager,
                digital.slovensko.autogram.core.SignatureTokenSettings settings) {
            try {
                return new eu.europa.esig.dss.token.Pkcs12SignatureToken(
                        MachineCliAppTest.class.getResource("/digital/slovensko/autogram/test.keystore").getFile(),
                        new KeyStore.PasswordProtection(new char[0]));
            } catch (IOException exception) {
                throw new RuntimeException(exception);
            }
        }
    }
}
