package digital.slovensko.autogram.ui.machine;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParseException;
import com.google.gson.JsonParser;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;

import java.io.IOException;
import java.io.Reader;
import java.util.Set;

public final class MachineProtocolCodec {
    public static final int VERSION = 1;

    private static final Set<String> REQUEST_FIELDS = Set.of("protocolVersion", "requestId", "operation", "payload");

    private final Gson gson = new GsonBuilder().disableHtmlEscaping().create();

    public MachineRequest decodeRequest(Reader reader) {
        try {
            var jsonReader = new JsonReader(reader);
            JsonElement element = JsonParser.parseReader(jsonReader);
            if (!element.isJsonObject() || jsonReader.peek() != JsonToken.END_DOCUMENT) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            var requestObject = element.getAsJsonObject();
            validateRequestEnvelope(requestObject);
            MachineRequest request = gson.fromJson(requestObject, MachineRequest.class);
            return request;
        } catch (IOException | JsonParseException exception) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST", exception);
        }
    }

    public String encodeEvent(MachineEvent event) {
        if (event == null || event.protocolVersion() != VERSION) {
            throw new MachineProtocolException("PROTOCOL_INVALID_EVENT");
        }
        return gson.toJson(event);
    }

    private static void validateRequestEnvelope(JsonObject request) {
        if (request.keySet().stream().anyMatch(field -> !REQUEST_FIELDS.contains(field))
                || !isVersionOne(request.get("protocolVersion"))
                || !isNonBlankString(request.get("requestId"))
                || !isString(request.get("operation"))
                || !isObject(request.get("payload"))) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
    }

    private static boolean isVersionOne(JsonElement element) {
        return element != null
                && element.isJsonPrimitive()
                && element.getAsJsonPrimitive().isNumber()
                && element.getAsBigDecimal().compareTo(java.math.BigDecimal.valueOf(VERSION)) == 0;
    }

    private static boolean isNonBlankString(JsonElement element) {
        return isString(element) && !element.getAsString().isBlank();
    }

    private static boolean isString(JsonElement element) {
        return element != null && element.isJsonPrimitive() && element.getAsJsonPrimitive().isString();
    }

    private static boolean isObject(JsonElement element) {
        return element != null && element.isJsonObject();
    }
}
