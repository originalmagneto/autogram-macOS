package digital.slovensko.autogram.ui.machine;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.Options;
import org.junit.jupiter.api.Test;

import java.io.PrintWriter;
import java.io.StringReader;
import java.io.StringWriter;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MachinePrivacyTest {
    @Test
    void unknownErrorOutputExcludesPinPathAndExceptionDetails() throws Exception {
        var output = new StringWriter();
        var request = "{\"protocolVersion\":1,\"requestId\":\"request-1\",\"operation\":\"INSPECT\","
                + "\"payload\":{\"files\":[{\"id\":\"file-1\",\"source\":\"/private/client.pdf\","
                + "\"target\":\"/private/signed.pdf\"}]}}";

        var code = MachineCliApp.start(commandLine("INSPECT"), new StringReader(request), new PrintWriter(output),
                new PrintWriter(new StringWriter()), new MachineDriverService(), new MachineInspectionService(),
                () -> { throw new RuntimeException("1234 /private/client.pdf ExampleException"); });

        assertEquals(70, code);
        assertTrue(output.toString().contains("INTERNAL_ERROR"));
        assertFalse(output.toString().contains("1234"));
        assertFalse(output.toString().contains("/private/client.pdf"));
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
