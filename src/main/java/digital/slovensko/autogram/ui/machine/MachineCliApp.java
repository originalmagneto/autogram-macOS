package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonElement;
import com.google.gson.JsonParseException;
import com.google.gson.JsonParser;
import org.apache.commons.cli.CommandLine;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.Reader;
import java.io.StringReader;

public final class MachineCliApp {
    private static final int USAGE_ERROR = 64;

    private MachineCliApp() {
    }

    public static int start(CommandLine commandLine, Reader input, PrintWriter output, PrintWriter error) {
        var writer = new MachineEventWriter(output);
        String rawRequest;
        try {
            rawRequest = readRequest(input);
        } catch (IOException exception) {
            return fail(writer, "unknown", "PROTOCOL_INVALID_REQUEST");
        }

        try {
            var request = new MachineProtocolCodec().decodeRequest(new StringReader(rawRequest));
            MachineRequestValidator.validate(commandLine, request);
            return fail(writer, request.requestId(), "OPERATION_NOT_AVAILABLE");
        } catch (MachineProtocolException exception) {
            return fail(writer, requestId(rawRequest), errorCode(exception, rawRequest));
        }
    }

    private static String readRequest(Reader input) throws IOException {
        var request = new StringBuilder();
        var buffer = new char[4096];
        int count;
        while ((count = input.read(buffer)) != -1) {
            request.append(buffer, 0, count);
        }
        return request.toString();
    }

    private static int fail(MachineEventWriter writer, String sessionId, String code) {
        var payload = new com.google.gson.JsonObject();
        payload.addProperty("code", code);
        writer.write("session.failed", sessionId, null, payload);
        return USAGE_ERROR;
    }

    private static String errorCode(MachineProtocolException exception, String rawRequest) {
        return hasUnsupportedProtocolVersion(rawRequest) ? "PROTOCOL_UNSUPPORTED_VERSION" : exception.getMessage();
    }

    private static boolean hasUnsupportedProtocolVersion(String rawRequest) {
        try {
            JsonElement element = JsonParser.parseString(rawRequest);
            if (!element.isJsonObject()) {
                return false;
            }
            var version = element.getAsJsonObject().get("protocolVersion");
            return version != null
                    && version.isJsonPrimitive()
                    && version.getAsJsonPrimitive().isNumber()
                    && version.getAsBigDecimal().compareTo(java.math.BigDecimal.valueOf(MachineProtocolCodec.VERSION)) != 0;
        } catch (JsonParseException exception) {
            return false;
        }
    }

    private static String requestId(String rawRequest) {
        try {
            JsonElement element = JsonParser.parseString(rawRequest);
            if (!element.isJsonObject()) {
                return "unknown";
            }
            var requestId = element.getAsJsonObject().get("requestId");
            return requestId != null && requestId.isJsonPrimitive() && requestId.getAsJsonPrimitive().isString()
                    ? requestId.getAsString()
                    : "unknown";
        } catch (JsonParseException exception) {
            return "unknown";
        }
    }
}
