package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MachineErrorMapperTest {
    private final MachineErrorMapper mapper = new MachineErrorMapper();

    @Test
    void mapsProtocolAndUnavailableErrorsToStableExitCodes() {
        assertEquals(64, mapper.exitCode(new MachineProtocolException("PROTOCOL_INVALID_REQUEST")));
        assertEquals(69, mapper.exitCode(new MachineProtocolException("DRIVER_UNAVAILABLE")));
    }

    @Test
    void mapsUnknownExceptionsToInternalError() {
        var mapped = mapper.map(new RuntimeException("sensitive failure"));

        assertEquals("INTERNAL_ERROR", mapped.code());
        assertEquals(70, mapper.exitCode(new RuntimeException("sensitive failure")));
    }
}
