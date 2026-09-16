package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class MachineSecretUITest {
    @Test
    void handsOverAnEnteredPin() {
        try (var ui = new MachineSecretUI("1234".toCharArray())) {
            assertArrayEquals("1234".toCharArray(), ui.getKeystorePassword());
            assertArrayEquals("1234".toCharArray(), ui.getContextSpecificPassword());
        }
    }

    /// The app sends this placeholder for an eID, whose BOK is typed in the eID
    /// client's own window. It must never reach a card as a PIN or BOK, where a
    /// wrong value counts as a failed attempt.
    @Test
    void neverHandsTheProtectedPathPlaceholderToACard() {
        try (var ui = new MachineSecretUI(MachineSecretUI.PROTECTED_AUTHENTICATION_PATH_PLACEHOLDER.toCharArray())) {
            assertNull(ui.getKeystorePassword());
            assertNull(ui.getContextSpecificPassword());
        }
    }
}
