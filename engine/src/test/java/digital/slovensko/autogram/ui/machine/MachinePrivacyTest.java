package digital.slovensko.autogram.ui.machine;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.Options;
import org.junit.jupiter.api.Test;

import java.io.PrintWriter;
import java.io.StringReader;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.io.TempDir;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MachinePrivacyTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void unknownErrorOutputExcludesPinPathAndExceptionDetails() throws Exception {
        // INSPECT never consults the trust initializer, so an unknown failure has to come from a
        // component the SIGN path actually uses: the signing service factory.
        var source = Files.writeString(temporaryDirectory.resolve("client.pdf"), "%PDF-1.7\nsource\n%%EOF").toRealPath();
        var target = temporaryDirectory.toRealPath().resolve("signed.pdf");
        var output = new StringWriter();
        var request = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"SIGN\",\"payload\":{"
                + "\"driver\":\"fake\",\"certificateSerial\":\"123\",\"pin\":\"1234\","
                + "\"signatureLevel\":\"PAdES_BASELINE_T\",\"timestamp\":{\"required\":true,"
                + "\"servers\":[\"https://tsa.example.test\"]},\"files\":[{\"id\":\"file-1\",\"source\":\""
                + source + "\",\"target\":\"" + target + "\"}]}}";
        var failingFactory = (MachineCliApp.SigningServiceFactory) (writer, inspection, trust) -> {
            throw new RuntimeException("1234 " + source + " ExampleException");
        };

        var code = MachineCliApp.start(commandLine("SIGN"), new StringReader(request), new PrintWriter(output),
                new PrintWriter(new StringWriter()), new MachineDriverService(), new MachineInspectionService(),
                () -> { }, failingFactory);

        assertEquals(70, code, output.toString());
        assertTrue(output.toString().contains("INTERNAL_ERROR"));
        assertFalse(output.toString().contains("1234"));
        assertFalse(output.toString().contains(source.toString()));
        assertFalse(output.toString().contains("ExampleException"));
    }

    @Test
    void terminalEventIsFlushedBeforeMachineModeReturns() throws Exception {
        var output = new FlushTrackingWriter();
        var request = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"CAPABILITIES\",\"payload\":{}}";

        var code = MachineCliApp.start(commandLine("CAPABILITIES"), new StringReader(request), new PrintWriter(output),
                new PrintWriter(new StringWriter()), new MachineDriverService());

        assertEquals(0, code);
        assertTrue(output.toString().contains("session.completed"));
        assertTrue(output.flushed);
    }

    private static final class FlushTrackingWriter extends StringWriter {
        private boolean flushed;

        @Override
        public void flush() {
            flushed = true;
        }
    }

    private static CommandLine commandLine(String operation) throws Exception {
        return new DefaultParser().parse(new Options()
                        .addOption(null, "machine-readable", false, "")
                        .addOption(null, "protocol-version", true, "")
                        .addOption(null, "operation", true, ""),
                new String[] { "--machine-readable", "--protocol-version", "1", "--operation", operation });
    }
}
