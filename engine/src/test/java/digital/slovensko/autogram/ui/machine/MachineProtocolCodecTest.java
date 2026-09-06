package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

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

    @Test
    void rejectsUnsupportedProtocolVersion() {
        var input = new StringReader("{\"protocolVersion\":2,\"requestId\":\"a\",\"operation\":\"CAPABILITIES\",\"payload\":{}}");

        assertThrows(MachineProtocolException.class, () -> new MachineProtocolCodec().decodeRequest(input));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "{\"requestId\":\"a\",\"operation\":\"CAPABILITIES\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"operation\":\"CAPABILITIES\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\"a\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\"a\",\"operation\":\"CAPABILITIES\"}",
            "{\"protocolVersion\":1,\"requestId\":null,\"operation\":\"CAPABILITIES\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\" \",\"operation\":\"CAPABILITIES\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\"a\",\"operation\":null,\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\"a\",\"operation\":\"CAPABILITIES\",\"payload\":null}",
            "{\"protocolVersion\":1,\"requestId\":\"a\",\"operation\":\"CAPABILITIES\",\"payload\":{},\"unexpected\":true}"
    })
    void rejectsInvalidRequestEnvelope(String json) {
        assertThrows(MachineProtocolException.class,
                () -> new MachineProtocolCodec().decodeRequest(new StringReader(json)));
    }

    @Test
    void rejectsNonVersionOneEvent() {
        var event = new MachineEvent(2, "session.started", "session-1", "2026-08-06T00:00:00Z", null, new JsonObject());

        assertThrows(MachineProtocolException.class, () -> new MachineProtocolCodec().encodeEvent(event));
    }

    @Test
    void encodesVersionOneEvent() {
        var event = new MachineEvent(1, "session.started", "session-1", "2026-08-06T00:00:00Z", null, new JsonObject());

        assertEquals("{\"protocolVersion\":1,\"type\":\"session.started\",\"sessionId\":\"session-1\",\"emittedAt\":\"2026-08-06T00:00:00Z\",\"payload\":{}}",
                new MachineProtocolCodec().encodeEvent(event));
    }
}
