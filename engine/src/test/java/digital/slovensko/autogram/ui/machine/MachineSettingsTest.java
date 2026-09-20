package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;

class MachineSettingsTest {
    @Test
    void secureStoreUsesTheCardSlotWhenNoSlotIsConfigured() {
        assertEquals(-1, MachineSettings.secureStoreSlotIndex(-1));
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
    void machineSettingsLeaveSecureStoreUnsetSoTheProbeCanPickTheTokenSlot() {
        var settings = new MachineSettings();

        assertEquals(-1, settings.getDriverSlotIndex("secure_store"));
        assertNull(settings.getEform());
    }
}
