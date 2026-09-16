package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MachineSettingsTest {
    @Test
    void secureStoreUsesTheCardSlotWhenNoSlotIsConfigured() {
        assertEquals(1, MachineSettings.secureStoreSlotIndex(-1));
    }

    @Test
    void secureStoreKeepsAConfiguredSlot() {
        assertEquals(0, MachineSettings.secureStoreSlotIndex(0));
        assertEquals(3, MachineSettings.secureStoreSlotIndex(3));
    }

    /// UserSettings ties "force context-specific login" to bulk mode, and the machine
    /// session runs in bulk mode. On an eID (CKF_PROTECTED_AUTHENTICATION_PATH) that
    /// sent a PIN from the app to the card as the BOK for every signature, and a
    /// wrong one spends a BOK attempt. The eID client asks for the BOK itself.
    @Test
    void machineModeNeverForcesAProgrammaticLoginOnProtectedTokens() {
        assertFalse(new MachineSettings(true).getForceContextSpecificLoginEnabled());
        assertFalse(new MachineSettings(false).getForceContextSpecificLoginEnabled());
    }

    @Test
    void machineSettingsNeverLeaveSecureStoreOnTheUnsetSlot() {
        var settings = new MachineSettings();

        // -1 would make NativePkcs11SignatureToken fall back to slot 0, the empty SecureStore reader.
        assertTrue(settings.getDriverSlotIndex("secure_store") >= 0);
        assertNull(settings.getEform());
    }
}
