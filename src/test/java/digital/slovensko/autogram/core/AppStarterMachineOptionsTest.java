package digital.slovensko.autogram.core;

import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
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

    @Test
    void routesMachineCliWithoutIntelCleanupBranch() throws Exception {
        var commandLine = AppStarter.parse(new String[] {
                "--cli", "--machine-readable", "--protocol-version", "1", "--operation", "CAPABILITIES"
        });
        var humanCalled = new AtomicBoolean();
        var machineCalled = new AtomicBoolean();

        var exitCode = AppStarter.dispatchCli(commandLine,
                ignored -> {
                    humanCalled.set(true);
                    return 1;
                },
                ignored -> {
                    machineCalled.set(true);
                    return 0;
                });

        assertEquals(0, exitCode);
        assertTrue(machineCalled.get());
        assertFalse(humanCalled.get());
        assertFalse(AppStarter.requiresIntelCliCleanup(commandLine));
    }
}
