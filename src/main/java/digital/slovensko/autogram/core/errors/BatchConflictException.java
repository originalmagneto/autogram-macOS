package digital.slovensko.autogram.core.errors;

public class BatchConflictException extends AutogramException {
    public BatchConflictException() {
        super();
    }

    public BatchConflictException(String description) {
        super("Iné hromadné podpisovanie už prebieha", "", description);
    }
}
