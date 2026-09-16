package digital.slovensko.autogram.ui.machine;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
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

    @Test
    void machineSettingsNeverLeaveSecureStoreOnTheUnsetSlot() {
        var settings = new MachineSettings();

        // -1 would make NativePkcs11SignatureToken fall back to slot 0, the empty SecureStore reader.
        assertTrue(settings.getDriverSlotIndex("secure_store") >= 0);
        assertNull(settings.getEform());
    }
}
