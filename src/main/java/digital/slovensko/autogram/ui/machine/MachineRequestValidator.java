package digital.slovensko.autogram.ui.machine;

import org.apache.commons.cli.CommandLine;

import java.util.Locale;

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

    private static MachineOperation parseOperation(String operation) {
        try {
            return MachineOperation.valueOf(operation.toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST", exception);
        }
    }
}
