package digital.slovensko.autogram.core;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AppStarterMachineOptionsTest {
    @Test
    void parsesMachineCliOptions() throws Exception {
        var commandLine = AppStarter.parse(new String[] {
                "--cli", "--machine-readable", "--protocol-version", "1", "--operation", "CAPABILITIES"
        });

        assertTrue(commandLine.hasOption("cli"));
        assertTrue(commandLine.hasOption("machine-readable"));
        assertEquals("1", commandLine.getOptionValue("protocol-version"));
        assertEquals("CAPABILITIES", commandLine.getOptionValue("operation"));
    }
}
