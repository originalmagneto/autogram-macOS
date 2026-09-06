package digital.slovensko.autogram.core.errors;

public class SigningParametersException extends AutogramException {
    public SigningParametersException(Error error) {
        super(error.toErrorCode());
    }

    public SigningParametersException(String message, String description) {
        super("Neplatné parametre", message, description);
    }

    public SigningParametersException(String message, String description, Throwable cause) {
        super("Neplatné parametre", message, description, cause);
    }

    public enum Error {
        NO_LEVEL, EMPTY_DOCUMENT, NO_MIME_TYPE, WRONG_MIME_TYPE, XSLT_NO_XDC;

        private String toErrorCode() {
            return "SigningParametersException." + this.name();
        }
    }
}
