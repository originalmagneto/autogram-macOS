package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;
import digital.slovensko.autogram.core.errors.InitializationFailedException;
import digital.slovensko.autogram.core.errors.PINIncorrectException;
import digital.slovensko.autogram.core.errors.PINLockedException;
import digital.slovensko.autogram.core.errors.TokenNotRecognizedException;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MachineErrorMapperTest {
    private final MachineErrorMapper mapper = new MachineErrorMapper();

    @Test
    void mapsProtocolAndUnavailableErrorsToStableExitCodes() {
        assertEquals(64, mapper.exitCode(new MachineProtocolException("PROTOCOL_INVALID_REQUEST")));
        assertEquals(69, mapper.exitCode(new MachineProtocolException("DRIVER_UNAVAILABLE")));
    }

    @Test
    void mapsUnknownExceptionsToInternalError() {
        var mapped = mapper.map(new RuntimeException("sensitive failure"));

        assertEquals("INTERNAL_ERROR", mapped.code());
        assertEquals(70, mapper.exitCode(new RuntimeException("sensitive failure")));
    }

    @Test
    void mapsMissingCardToTokenNotPresent() {
        var wrapped = new MachineProtocolException("DRIVER_UNAVAILABLE",
                new InitializationFailedException());
        var mapped = mapper.map(wrapped);

        assertEquals("TOKEN_NOT_PRESENT", mapped.code());
        assertEquals(69, mapper.exitCode(wrapped));
        assertEquals("TOKEN_NOT_RECOGNIZED", mapper.map(new TokenNotRecognizedException()).code());
        assertEquals("PIN_LOCKED", mapper.map(new PINLockedException()).code());
        assertEquals(64, mapper.exitCode(new PINLockedException()));
    }

    @Test
    void internalErrorNamesExceptionClassesButNotMessages() {
        var mapped = mapper.map(new IllegalStateException("1234 /private/client.pdf",
                new RuntimeException("secret")));

        assertEquals("INTERNAL_ERROR", mapped.code());
        assertEquals("The machine request could not be completed (IllegalStateException <- RuntimeException).",
                mapped.fallbackMessage());
    }

    @Test
    void mapsIncorrectPinToStableSafeError() {
        var mapped = mapper.map(new PINIncorrectException());

        assertEquals("PIN_INCORRECT", mapped.code());
        assertEquals("The supplied PIN was not accepted.", mapped.fallbackMessage());
        assertEquals(64, mapper.exitCode(new PINIncorrectException()));
    }
}
