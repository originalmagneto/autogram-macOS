package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonParser;
import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.Options;
import org.junit.jupiter.api.Test;

import java.io.PrintWriter;
import java.io.Reader;
import java.io.StringReader;
import java.io.StringWriter;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MachineCliAppTest {
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
}
