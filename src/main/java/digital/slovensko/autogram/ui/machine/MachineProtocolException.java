package digital.slovensko.autogram.ui.machine;

public final class MachineProtocolException extends RuntimeException {
    public MachineProtocolException(String message) {
        super(message);
    }

    public MachineProtocolException(String message, Throwable cause) {
        super(message, cause);
    }
}
