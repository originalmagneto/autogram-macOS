package digital.slovensko.autogram.ui.machine;

import eu.europa.esig.dss.enumerations.Indication;
import eu.europa.esig.dss.enumerations.SignatureLevel;
import eu.europa.esig.dss.enumerations.SignatureQualification;
import eu.europa.esig.dss.enumerations.TimestampQualification;
import eu.europa.esig.dss.simplereport.SimpleReport;
import eu.europa.esig.dss.simplereport.jaxb.XmlTimestamp;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.concurrent.AbstractExecutorService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class MachineInspectionServiceTest {
    @Test
    void dispatchesInspectionOnlyAfterTrustedListInitialization() throws Exception {
        var report = reportWithOneQualifiedTimestamp();
        var inspectionService = new MachineInspectionService(path -> report);
        var stdout = new java.io.StringWriter();
        var input = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"INSPECT\",\"payload\":{\"path\":\"/selected/signed.pdf\"}}";
        var trustInitialized = new AtomicBoolean();

        var code = MachineCliApp.start(commandLine("INSPECT"), new java.io.StringReader(input), new java.io.PrintWriter(stdout),
                new java.io.PrintWriter(new java.io.StringWriter()), new MachineDriverService(), inspectionService,
                () -> trustInitialized.set(true));

        var events = java.util.Arrays.stream(stdout.toString().strip().split("\\n"))
                .map(com.google.gson.JsonParser::parseString)
                .map(element -> element.getAsJsonObject())
                .toList();
        assertEquals(0, code);
        assertTrue(trustInitialized.get());
        assertEquals(List.of("session.started", "inspection.completed", "session.completed"),
                events.stream().map(event -> event.get("type").getAsString()).toList());
        assertEquals("/selected/signed.pdf", events.get(1).get("fileId").getAsString());
        assertTrue(events.get(1).getAsJsonObject("payload").getAsJsonArray("signatures").get(0).getAsJsonObject()
                .get("qualifiedTimestampValid").getAsBoolean());
    }

    @Test
    void reportsTrustedListFailureWithoutInspectingTheFile() throws Exception {
        var inspectionCalled = new AtomicBoolean();
        var inspectionService = new MachineInspectionService(path -> {
            inspectionCalled.set(true);
            return reportWithOneQualifiedTimestamp();
        });
        var stdout = new java.io.StringWriter();
        var input = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"INSPECT\",\"payload\":{\"path\":\"/selected/signed.pdf\"}}";

        var code = MachineCliApp.start(commandLine("INSPECT"), new java.io.StringReader(input), new java.io.PrintWriter(stdout),
                new java.io.PrintWriter(new java.io.StringWriter()), new MachineDriverService(), inspectionService,
                () -> { throw new MachineProtocolException("TRUSTED_LIST_UNAVAILABLE"); });

        var events = java.util.Arrays.stream(stdout.toString().strip().split("\\n"))
                .map(com.google.gson.JsonParser::parseString)
                .map(element -> element.getAsJsonObject())
                .toList();
        assertEquals(64, code);
        assertFalse(inspectionCalled.get());
        assertEquals(List.of("session.started", "session.failed"),
                events.stream().map(event -> event.get("type").getAsString()).toList());
        assertEquals("TRUSTED_LIST_UNAVAILABLE", events.get(1).getAsJsonObject("payload").get("code").getAsString());
    }

    @Test
    void mapsSignatureAndTimestampQualificationsToSeparateFields() {
        var report = reportWithOneQualifiedTimestamp();
        var payload = new MachineInspectionService(path -> report).inspect(Path.of("signed.pdf"));

        var signature = payload.getAsJsonArray("signatures").get(0).getAsJsonObject();
        assertEquals("PAdES_BASELINE_T", signature.get("format").getAsString());
        assertEquals("Jane Signer", signature.get("signerDisplayName").getAsString());
        assertEquals("QESIG", signature.get("signerCertificateQualification").getAsString());
        assertEquals("2026-08-06T10:15:30Z", signature.get("signingTime").getAsString());
        assertTrue(signature.get("valid").getAsBoolean());
        assertEquals("TOTAL_PASSED", signature.get("indication").getAsString());
        assertTrue(signature.get("qualifiedTimestampValid").getAsBoolean());

        var timestamp = signature.getAsJsonArray("timestamps").get(0).getAsJsonObject();
        assertEquals("2026-08-06T10:16:30Z", timestamp.get("productionTime").getAsString());
        assertEquals("Qualified TSA", timestamp.get("producer").getAsString());
        assertTrue(timestamp.get("valid").getAsBoolean());
        assertEquals("QTSA", timestamp.get("qualification").getAsString());
    }

    @Test
    void readsSignatureStructureFromSampleSignedPdfWithoutTrustedListDownload() {
        var sample = Path.of(MachineInspectionServiceTest.class
                .getResource("/digital/slovensko/autogram/sample_signed.pdf").getFile());

        var report = MachineInspectionService.readStructuralReport(sample);

        assertNotNull(report);
        assertFalse(report.getSignatureIdList().isEmpty());
    }

    @Test
    void failsClosedAndClosesDedicatedExecutorWhenTrustedListsNeverLoad() {
        var executor = new ImmediateExecutorService();
        var initialized = new AtomicBoolean();
        var trust = new MachineTrustService(
                () -> executor,
                ignored -> initialized.set(true),
                () -> false,
                Duration.ZERO,
                Duration.ZERO);

        var failure = assertThrows(MachineProtocolException.class, trust::initialize);

        assertEquals("TRUSTED_LIST_UNAVAILABLE", failure.getMessage());
        assertTrue(initialized.get());
        assertTrue(executor.isShutdown());
    }

    @Test
    void waitsForInitializationBeforeReadingTrustedListState() {
        var executor = new NeverRunsExecutorService();
        var trustedListStateRead = new AtomicBoolean();
        var trust = new MachineTrustService(
                () -> executor,
                ignored -> {
                },
                () -> {
                    trustedListStateRead.set(true);
                    return false;
                },
                Duration.ZERO,
                Duration.ZERO);

        var failure = assertThrows(MachineProtocolException.class, trust::initialize);

        assertEquals("TRUSTED_LIST_UNAVAILABLE", failure.getMessage());
        assertFalse(trustedListStateRead.get());
        assertTrue(executor.isShutdown());
    }

    @Test
    void closesDedicatedExecutorAfterTrustedListsLoad() {
        var executor = new ImmediateExecutorService();
        var initialized = new AtomicBoolean();
        var trust = new MachineTrustService(
                () -> executor,
                ignored -> initialized.set(true),
                initialized::get,
                Duration.ofSeconds(1),
                Duration.ZERO);

        trust.initialize();

        assertTrue(executor.isShutdown());
    }

    @Test
    void waitsForValidatorInitializationBeforeCheckingTrustedLists() {
        var executor = new ImmediateExecutorService();
        var initialized = new AtomicBoolean();
        var checks = new AtomicInteger();
        var trust = new MachineTrustService(
                () -> executor,
                ignored -> initialized.set(true),
                () -> {
                    if (checks.getAndIncrement() == 0) {
                        throw new NullPointerException("validator is not initialized yet");
                    }
                    return initialized.get();
                },
                Duration.ofSeconds(1),
                Duration.ofMillis(1));

        trust.initialize();

        assertTrue(executor.isShutdown());
    }

    private static SimpleReport reportWithOneQualifiedTimestamp() {
        var report = mock(SimpleReport.class);
        var timestamp = new XmlTimestamp();
        timestamp.setId("ts-1");
        var signingTime = Date.from(Instant.parse("2026-08-06T10:15:30Z"));
        var productionTime = Date.from(Instant.parse("2026-08-06T10:16:30Z"));
        when(report.getSignatureIdList()).thenReturn(List.of("sig-1"));
        when(report.getSignatureFormat("sig-1")).thenReturn(SignatureLevel.PAdES_BASELINE_T);
        when(report.getSignedBy("sig-1")).thenReturn("Jane Signer");
        when(report.getSignatureQualification("sig-1")).thenReturn(SignatureQualification.QESIG);
        when(report.getSigningTime("sig-1")).thenReturn(signingTime);
        when(report.isValid("sig-1")).thenReturn(true);
        when(report.getIndication("sig-1")).thenReturn(Indication.TOTAL_PASSED);
        when(report.getSignatureTimestamps("sig-1")).thenReturn(List.of(timestamp));
        when(report.getProductionTime("ts-1")).thenReturn(productionTime);
        when(report.getProducedBy("ts-1")).thenReturn("Qualified TSA");
        when(report.isValid("ts-1")).thenReturn(true);
        when(report.getTimestampQualification("ts-1")).thenReturn(TimestampQualification.QTSA);
        return report;
    }

    private static org.apache.commons.cli.CommandLine commandLine(String operation) throws Exception {
        var options = new org.apache.commons.cli.Options()
                .addOption(null, "machine-readable", false, "")
                .addOption(null, "protocol-version", true, "")
                .addOption(null, "operation", true, "");
        return new org.apache.commons.cli.DefaultParser().parse(options,
                new String[] { "--machine-readable", "--protocol-version", "1", "--operation", operation });
    }

    private static final class ImmediateExecutorService extends AbstractExecutorService {
        private boolean shutdown;

        @Override
        public void shutdown() {
            shutdown = true;
        }

        @Override
        public List<Runnable> shutdownNow() {
            shutdown = true;
            return List.of();
        }

        @Override
        public boolean isShutdown() {
            return shutdown;
        }

        @Override
        public boolean isTerminated() {
            return shutdown;
        }

        @Override
        public boolean awaitTermination(long timeout, TimeUnit unit) {
            return shutdown;
        }

        @Override
        public void execute(Runnable command) {
            command.run();
        }
    }

    private static final class NeverRunsExecutorService extends AbstractExecutorService {
        private boolean shutdown;

        @Override
        public void shutdown() {
            shutdown = true;
        }

        @Override
        public List<Runnable> shutdownNow() {
            shutdown = true;
            return List.of();
        }

        @Override
        public boolean isShutdown() {
            return shutdown;
        }

        @Override
        public boolean isTerminated() {
            return shutdown;
        }

        @Override
        public boolean awaitTermination(long timeout, TimeUnit unit) {
            return shutdown;
        }

        @Override
        public void execute(Runnable command) {
        }
    }
}
