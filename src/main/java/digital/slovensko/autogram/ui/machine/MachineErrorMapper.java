package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.errors.PINIncorrectException;

import java.util.Set;

public final class MachineErrorMapper {
    static final int COMPLETED = 0;
    static final int REQUEST_ERROR = 64;
    static final int UNAVAILABLE = 69;
    static final int INTERNAL_FAILURE = 70;

    private static final Set<String> REQUEST_CODES = Set.of(
            "OPERATION_MISMATCH", "PROTOCOL_INVALID_EVENT", "PROTOCOL_INVALID_REQUEST",
            "PROTOCOL_UNSUPPORTED_VERSION", "SIGNATURE_LEVEL_REQUIRED", "TIMESTAMP_REQUIRED", "TSA_REQUIRED");
    private static final Set<String> UNAVAILABLE_CODES = Set.of(
            "DRIVER_NOT_FOUND", "DRIVER_UNAVAILABLE", "MACHINE_PLATFORM_UNSUPPORTED",
            "OUTPUT_PUBLISH_UNSUPPORTED", "SIGNING_UNAVAILABLE", "TRUSTED_LIST_UNAVAILABLE");
    private static final Set<String> INTERNAL_CODES = Set.of(
            "OUTPUT_CLEANUP_FAILED", "OUTPUT_TARGET_EXISTS", "OUTPUT_VALIDATION_FAILED", "OUTPUT_WRITE_FAILED",
            "SIGNING_FAILED");

    public MachineError map(Throwable exception) {
        if (exception instanceof PINIncorrectException) {
            return error("PIN_INCORRECT", "machine.error.pinIncorrect", "The supplied PIN was not accepted.", true,
                    "Verify the PIN and retry the request.");
        }
        if (exception instanceof MachineProtocolException protocolException) {
            return protocolError(protocolException.getMessage());
        }
        return error("INTERNAL_ERROR", "machine.error.internal", "The machine request could not be completed.", false,
                "Retry later or inspect the local application logs.");
    }

    public int exitCode(Throwable exception) {
        var code = map(exception).code();
        if (REQUEST_CODES.contains(code) || "PIN_INCORRECT".equals(code)) {
            return REQUEST_ERROR;
        }
        if (UNAVAILABLE_CODES.contains(code)) {
            return UNAVAILABLE;
        }
        return INTERNAL_FAILURE;
    }

    private static MachineError protocolError(String code) {
        if (REQUEST_CODES.contains(code)) {
            return error(code, "machine.error.request", "The machine request is invalid.", false,
                    "Correct the request and retry.");
        }
        if (UNAVAILABLE_CODES.contains(code)) {
            return error(code, "machine.error.unavailable", "A required local service is unavailable.", true,
                    "Connect the required token or service and retry.");
        }
        if (INTERNAL_CODES.contains(code)) {
            return error(code, "machine.error.internal", "The machine request could not be completed.", false,
                    "Retry later or inspect the local application logs.");
        }
        return error("INTERNAL_ERROR", "machine.error.internal", "The machine request could not be completed.", false,
                "Retry later or inspect the local application logs.");
    }

    private static MachineError error(String code, String messageKey, String fallbackMessage, boolean retryable,
            String recovery) {
        return new MachineError(code, messageKey, fallbackMessage, retryable, recovery);
    }
}
