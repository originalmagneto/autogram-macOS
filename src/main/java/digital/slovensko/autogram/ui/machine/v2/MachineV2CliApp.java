package digital.slovensko.autogram.ui.machine.v2;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import digital.slovensko.autogram.ui.machine.MachineDriverService;
import digital.slovensko.autogram.ui.machine.MachineInspectionService;
import digital.slovensko.autogram.ui.machine.MachineProtocolException;
import org.apache.commons.cli.CommandLine;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.Reader;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class MachineV2CliApp {
    private MachineV2CliApp() {
    }

    public static int start(CommandLine commandLine, Reader input, PrintWriter output, PrintWriter error) {
        return start(commandLine, input, output, error, new MachineDriverService(), new MachineInspectionService());
    }

    static int start(CommandLine commandLine, Reader input, PrintWriter output, PrintWriter error,
            MachineDriverService driverService, MachineInspectionService inspectionService) {
        var writer = new EventWriter(output);
        try {
            validateCommandLine(commandLine);
        } catch (MachineProtocolException exception) {
            writer.failed("unknown", exception.getMessage());
            return 64;
        }

        try (var lines = new BufferedReader(input)) {
            String line;
            while ((line = lines.readLine()) != null) {
                if (line.isBlank()) {
                    writer.failed("unknown", "PROTOCOL_INVALID_REQUEST");
                    continue;
                }
                handle(line, writer, driverService, inspectionService);
            }
        } catch (IOException exception) {
            error.println("Machine protocol v2 input could not be read.");
            error.flush();
            return 70;
        }
        return 0;
    }

    private static void handle(String line, EventWriter writer, MachineDriverService driverService,
            MachineInspectionService inspectionService) {
        var codec = new MachineV2ProtocolCodec();
        var requestId = MachineV2ProtocolCodec.requestId(line);
        try {
            var request = codec.decodeRequest(line);
            requestId = request.requestId();
            writer.started(requestId);
            dispatch(request, writer, driverService, inspectionService);
        } catch (MachineProtocolException exception) {
            writer.failed(requestId, exception.getMessage());
        } catch (Exception exception) {
            writer.failed(requestId, "INTERNAL_ERROR");
        }
    }

    private static void dispatch(MachineV2Request request, EventWriter writer, MachineDriverService driverService,
            MachineInspectionService inspectionService) {
        switch (request.operation()) {
            case CAPABILITIES -> capabilities(request, writer, driverService);
            case INSPECT -> inspect(request, writer, inspectionService);
            case CERTIFICATES -> certificates(request, writer, driverService);
            case SIGN, TIMESTAMP, VALIDATE -> throw new MachineProtocolException("OPERATION_UNAVAILABLE");
        }
    }

    private static void capabilities(MachineV2Request request, EventWriter writer, MachineDriverService driverService) {
        requireEmptyPayload(request.payload());
        var payload = driverService.capabilities();
        var visibleAppearance = new JsonObject();
        visibleAppearance.addProperty("renderedPng", true);
        var importedAssetTypes = new JsonArray();
        importedAssetTypes.add("image/png");
        importedAssetTypes.add("application/pdf");
        visibleAppearance.add("importedAssetTypes", importedAssetTypes);
        visibleAppearance.addProperty("arbitraryRotation", "RASTERIZED_IN_SWIFT");
        visibleAppearance.addProperty("fieldCoordinateSystem", "DSS_TOP_LEFT_PDF_POINTS");
        payload.add("visibleAppearance", visibleAppearance);
        writer.completed(request.requestId(), payload);
    }

    private static void inspect(MachineV2Request request, EventWriter writer, MachineInspectionService inspectionService) {
        for (var file : requiredFiles(request.payload())) {
            try {
                writer.write("inspection.completed", request.requestId(), file.id(),
                        inspectionService.inspect(java.nio.file.Path.of(file.source())));
            } catch (Exception exception) {
                var payload = new JsonObject();
                payload.addProperty("code", "INSPECTION_FAILED");
                writer.write("file.failed", request.requestId(), file.id(), payload);
            }
        }
        writer.completed(request.requestId(), new JsonObject());
    }

    private static void certificates(MachineV2Request request, EventWriter writer, MachineDriverService driverService) {
        var payload = request.payload();
        if (payload.size() != 2 || !isNonBlankString(payload.get("driver")) || !isNonBlankString(payload.get("pin"))) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        var pin = payload.get("pin").getAsString().toCharArray();
        try {
            writer.write("certificates.available", request.requestId(), null, driverService.certificates(
                    payload.get("driver").getAsString(), pin));
            writer.completed(request.requestId(), new JsonObject());
        } finally {
            Arrays.fill(pin, '\0');
        }
    }

    private static List<MachineFile> requiredFiles(JsonObject payload) {
        if (payload.size() != 1 || !payload.has("files") || !payload.get("files").isJsonArray()
                || payload.getAsJsonArray("files").isEmpty()) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        var files = new ArrayList<MachineFile>();
        for (JsonElement element : payload.getAsJsonArray("files")) {
            if (!element.isJsonObject()) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            var file = element.getAsJsonObject();
            if (file.size() != 3 || !isNonBlankString(file.get("id")) || !isNonBlankString(file.get("source"))
                    || !isNonBlankString(file.get("target"))) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            files.add(new MachineFile(file.get("id").getAsString(), file.get("source").getAsString(),
                    file.get("target").getAsString()));
        }
        return List.copyOf(files);
    }

    private static void validateCommandLine(CommandLine commandLine) {
        if (!commandLine.hasOption("machine-readable") || !commandLine.hasOption("protocol-version")) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        if (!Integer.toString(MachineV2ProtocolCodec.VERSION).equals(commandLine.getOptionValue("protocol-version"))) {
            throw new MachineProtocolException("PROTOCOL_UNSUPPORTED_VERSION");
        }
    }

    private static void requireEmptyPayload(JsonObject payload) {
        if (!payload.isEmpty()) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
    }

    private static boolean isNonBlankString(JsonElement value) {
        return value != null && value.isJsonPrimitive() && value.getAsJsonPrimitive().isString()
                && !value.getAsString().isBlank();
    }

    private record MachineFile(String id, String source, String target) {
    }

    private static final class EventWriter {
        private final PrintWriter output;
        private final MachineV2ProtocolCodec codec = new MachineV2ProtocolCodec();

        private EventWriter(PrintWriter output) {
            this.output = output;
        }

        private synchronized void started(String requestId) {
            write("request.started", requestId, null, new JsonObject());
        }

        private synchronized void completed(String requestId, JsonObject payload) {
            write("request.completed", requestId, null, payload);
        }

        private synchronized void failed(String requestId, String code) {
            var payload = new JsonObject();
            payload.addProperty("code", code == null ? "INTERNAL_ERROR" : code);
            write("request.failed", requestId, null, payload);
        }

        private synchronized void write(String type, String requestId, String fileId, JsonObject payload) {
            output.print(codec.encodeEvent(new MachineV2Event(MachineV2ProtocolCodec.VERSION, requestId, type,
                    Instant.now().toString(), fileId, payload == null ? new JsonObject() : payload)));
            output.print('\n');
            output.flush();
        }
    }
}
