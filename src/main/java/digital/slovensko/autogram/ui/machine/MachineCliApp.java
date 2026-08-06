package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParseException;
import com.google.gson.JsonParser;
import org.apache.commons.cli.CommandLine;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.Reader;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.List;

public final class MachineCliApp {
    private static final int USAGE_ERROR = 64;

    private MachineCliApp() {
    }

    public static int start(CommandLine commandLine, Reader input, PrintWriter output, PrintWriter error) {
        return start(commandLine, input, output, error, new MachineDriverService(), new MachineInspectionService(),
                new MachineTrustService()::initialize);
    }

    static int start(CommandLine commandLine, Reader input, PrintWriter output, PrintWriter error,
            MachineDriverService driverService) {
        return start(commandLine, input, output, error, driverService, new MachineInspectionService(),
                new MachineTrustService()::initialize);
    }

    static int start(CommandLine commandLine, Reader input, PrintWriter output, PrintWriter error,
            MachineDriverService driverService, MachineInspectionService inspectionService, Runnable trustInitializer) {
        var writer = new MachineEventWriter(output);
        try {
            MachineRequestValidator.validateCommandLine(commandLine);
        } catch (MachineProtocolException exception) {
            return fail(writer, "unknown", exception.getMessage());
        }

        String rawRequest;
        try {
            rawRequest = readRequest(input);
        } catch (IOException exception) {
            return fail(writer, "unknown", "PROTOCOL_INVALID_REQUEST");
        }

        try {
            var request = new MachineProtocolCodec().decodeRequest(new StringReader(rawRequest));
            MachineRequestValidator.validate(commandLine, request);
            return dispatch(writer, request, driverService, inspectionService, trustInitializer);
        } catch (MachineProtocolException exception) {
            return fail(writer, requestId(rawRequest), errorCode(exception, rawRequest));
        } catch (Exception exception) {
            return fail(writer, requestId(rawRequest), "OPERATION_FAILED");
        }
    }

    private static int dispatch(MachineEventWriter writer, MachineRequest request, MachineDriverService driverService,
            MachineInspectionService inspectionService, Runnable trustInitializer) {
        return switch (request.operation()) {
            case CAPABILITIES -> dispatchCapabilities(writer, request, driverService);
            case DRIVERS -> dispatchDrivers(writer, request, driverService);
            case CERTIFICATES -> dispatchCertificates(writer, request, driverService);
            case INSPECT -> dispatchInspection(writer, request, inspectionService, trustInitializer);
            case SIGN -> fail(writer, request.requestId(), "OPERATION_NOT_AVAILABLE");
        };
    }

    private static int dispatchCapabilities(MachineEventWriter writer, MachineRequest request, MachineDriverService driverService) {
        requireEmptyPayload(request.payload());
        writer.write("session.started", request.requestId(), null, new JsonObject());
        return complete(writer, request.requestId(), driverService.capabilities());
    }

    private static int dispatchDrivers(MachineEventWriter writer, MachineRequest request, MachineDriverService driverService) {
        requireEmptyPayload(request.payload());
        var payload = driverService.drivers();
        writer.write("session.started", request.requestId(), null, new JsonObject());
        writer.write("driver.detected", request.requestId(), null, payload);
        return complete(writer, request.requestId(), new JsonObject());
    }

    private static int dispatchCertificates(MachineEventWriter writer, MachineRequest request, MachineDriverService driverService) {
        var driver = requiredString(request.payload(), "driver");
        var pin = requiredString(request.payload(), "pin").toCharArray();
        try {
            writer.write("session.started", request.requestId(), null, new JsonObject());
            var payload = driverService.certificates(driver, pin);
            writer.write("certificates.available", request.requestId(), null, payload);
            return complete(writer, request.requestId(), new JsonObject());
        } finally {
            java.util.Arrays.fill(pin, '\0');
        }
    }

    private static int dispatchInspection(MachineEventWriter writer, MachineRequest request,
            MachineInspectionService inspectionService, Runnable trustInitializer) {
        var files = requiredInspectionFiles(request.payload());
        writer.write("session.started", request.requestId(), null, new JsonObject());
        trustInitializer.run();
        for (var file : files) {
            inspectFile(writer, request.requestId(), inspectionService, file);
        }
        return complete(writer, request.requestId(), new JsonObject());
    }

    private static void inspectFile(MachineEventWriter writer, String requestId, MachineInspectionService inspectionService,
            InspectFile file) {
        try {
            var source = java.nio.file.Path.of(file.source());
            writer.write("inspection.completed", requestId, file.id(), inspectionService.inspect(source));
        } catch (Exception exception) {
            var payload = new JsonObject();
            payload.addProperty("code", "INSPECTION_FAILED");
            writer.write("file.failed", requestId, file.id(), payload);
        }
    }

    private static int complete(MachineEventWriter writer, String requestId, JsonObject payload) {
        writer.write("session.completed", requestId, null, payload);
        return 0;
    }

    private static void requireEmptyPayload(JsonObject payload) {
        if (!payload.isEmpty()) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
    }

    private static String requiredString(JsonObject payload, String field) {
        if (payload.size() != 2
                || !payload.has(field)
                || !payload.has("driver")
                || !payload.has("pin")
                || !isNonBlankString(payload.get(field))) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        return payload.get(field).getAsString();
    }

    private static List<InspectFile> requiredInspectionFiles(JsonObject payload) {
        if (payload.size() != 1 || !payload.has("files") || !payload.get("files").isJsonArray()
                || payload.getAsJsonArray("files").isEmpty()) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        var files = new ArrayList<InspectFile>();
        for (var element : payload.getAsJsonArray("files")) {
            if (!element.isJsonObject()) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            var file = element.getAsJsonObject();
            if (file.size() != 3 || !file.has("id") || !file.has("source") || !file.has("target")
                    || !isNonBlankString(file.get("id")) || !isNonBlankString(file.get("source"))
                    || !isNonBlankString(file.get("target"))) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            files.add(new InspectFile(file.get("id").getAsString(), file.get("source").getAsString(),
                    file.get("target").getAsString()));
        }
        return files;
    }

    private static boolean isNonBlankString(JsonElement element) {
        return element != null
                && element.isJsonPrimitive()
                && element.getAsJsonPrimitive().isString()
                && !element.getAsString().isBlank();
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

    private record InspectFile(String id, String source, String target) {
    }
}
