package digital.slovensko.autogram.ui.machine;

import org.apache.commons.cli.CommandLine;

import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public final class MachineRequestValidator {
    private MachineRequestValidator() {
    }

    public static void validate(CommandLine commandLine, MachineRequest request) {
        validateCommandLine(commandLine);
        if (request.operation() == null) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        if (parseOperation(commandLine.getOptionValue("operation")) != request.operation()) {
            throw new MachineProtocolException("OPERATION_MISMATCH");
        }
    }

    public static void validateCommandLine(CommandLine commandLine) {
        if (!commandLine.hasOption("machine-readable")
                || !commandLine.hasOption("protocol-version")
                || !commandLine.hasOption("operation")) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        if (!Integer.toString(MachineProtocolCodec.VERSION).equals(commandLine.getOptionValue("protocol-version"))) {
            throw new MachineProtocolException("PROTOCOL_UNSUPPORTED_VERSION");
        }
    }

    public static void validateSign(SignRequest request) {
        if (request == null || isBlank(request.driver()) || isBlank(request.certificateSerial())
                || request.pin() == null || request.pin().length == 0 || request.files() == null || request.files().isEmpty()) {
            throw invalidRequest();
        }
        if (!"PAdES_BASELINE_T".equals(request.signatureLevel())) {
            throw new MachineProtocolException("SIGNATURE_LEVEL_REQUIRED");
        }
        validateTimestamp(request.timestamp());
        validateFiles(request.files());
    }

    private static void validateTimestamp(QualifiedTimestampRequest timestamp) {
        if (timestamp == null || !timestamp.required()) {
            throw new MachineProtocolException("TIMESTAMP_REQUIRED");
        }
        if (timestamp.servers() == null || timestamp.servers().stream().noneMatch(MachineRequestValidator::isSupportedTsaUrl)) {
            throw new MachineProtocolException("TSA_REQUIRED");
        }
    }

    private static void validateFiles(List<MachineFile> files) {
        Set<Path> targets = new HashSet<>();
        for (var file : files) {
            if (file == null || isBlank(file.id()) || isBlank(file.source()) || isBlank(file.target())) {
                throw invalidRequest();
            }
            var source = canonicalSource(file.source());
            var target = canonicalTarget(file.target());
            if (source.equals(target) || Files.exists(target, LinkOption.NOFOLLOW_LINKS) || !targets.add(target)
                    || !isPdf(source)) {
                throw invalidRequest();
            }
        }
    }

    private static Path canonicalSource(String value) {
        var path = strictAbsolutePath(value);
        try {
            var canonical = path.toRealPath();
            if (!Files.isRegularFile(canonical) || !canonical.equals(path)) {
                throw invalidRequest();
            }
            return canonical;
        } catch (IOException exception) {
            throw invalidRequest();
        }
    }

    private static Path canonicalTarget(String value) {
        var path = strictAbsolutePath(value);
        try {
            var parent = path.getParent();
            if (parent == null || !parent.toRealPath().equals(parent)) {
                throw invalidRequest();
            }
            return path;
        } catch (IOException exception) {
            throw invalidRequest();
        }
    }

    private static Path strictAbsolutePath(String value) {
        try {
            var path = Path.of(value);
            if (!path.isAbsolute() || !path.equals(path.normalize()) || path.getNameCount() == 0) {
                throw invalidRequest();
            }
            return path;
        } catch (RuntimeException exception) {
            if (exception instanceof MachineProtocolException protocolException) {
                throw protocolException;
            }
            throw invalidRequest();
        }
    }

    private static boolean isPdf(Path source) {
        try (var stream = Files.newInputStream(source)) {
            var header = stream.readNBytes(5);
            return "%PDF-".equals(new String(header, StandardCharsets.ISO_8859_1));
        } catch (IOException exception) {
            return false;
        }
    }

    private static boolean isSupportedTsaUrl(String value) {
        if (isBlank(value)) {
            return false;
        }
        try {
            var uri = new URI(value);
            return ("http".equalsIgnoreCase(uri.getScheme()) || "https".equalsIgnoreCase(uri.getScheme()))
                    && uri.getHost() != null;
        } catch (URISyntaxException exception) {
            return false;
        }
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private static MachineProtocolException invalidRequest() {
        return new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
    }

    private static MachineOperation parseOperation(String operation) {
        try {
            return MachineOperation.valueOf(operation.toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST", exception);
        }
    }
}
