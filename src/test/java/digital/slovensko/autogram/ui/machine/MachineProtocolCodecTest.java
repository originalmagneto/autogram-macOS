package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;

import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class MachineProtocolCodecTest {
    @Test
    void decodesVersionOneCapabilitiesFixture() throws Exception {
        try (var reader = Files.newBufferedReader(Path.of("protocol/v1/fixtures/capabilities-request.json"))) {
            var request = new MachineProtocolCodec().decodeRequest(reader);
            assertEquals(1, request.protocolVersion());
            assertEquals(MachineOperation.CAPABILITIES, request.operation());
            assertEquals("request-1", request.requestId());
        }
    }

    @Test
    void rejectsTrailingInput() {
        var input = new StringReader("{\"protocolVersion\":1,\"requestId\":\"a\",\"operation\":\"CAPABILITIES\",\"payload\":{}} {} ");
        assertThrows(MachineProtocolException.class, () -> new MachineProtocolCodec().decodeRequest(input));
    }
}
