package digital.slovensko.autogram.drivers;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class PKCS11TokenPresenceProbeTest {
    @Test
    void emptyReaderThenCardUsesSlotOne() {
        assertEquals(1, PKCS11TokenPresenceProbe.slotListIndexOf(new long[]{1, 2}, new long[]{2}));
    }

    @Test
    void singleReaderUsesSlotZero() {
        assertEquals(0, PKCS11TokenPresenceProbe.slotListIndexOf(new long[]{7}, new long[]{7}));
    }

    @Test
    void noTokenReturnsUnset() {
        assertEquals(-1, PKCS11TokenPresenceProbe.slotListIndexOf(new long[]{1, 2}, new long[]{}));
        assertEquals(-1, PKCS11TokenPresenceProbe.slotListIndexOf(new long[]{1}, null));
    }
}
