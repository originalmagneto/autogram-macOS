package digital.slovensko.autogram.ui.gui;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OverlaySpecTests {
    @Test
    void compactSpecUsesCompactSizePreset() {
        var spec = OverlaySpec.compact();
        assertEquals(OverlaySizePreset.COMPACT, spec.sizePreset());
        assertTrue(spec.trapFocus());
    }

    @Test
    void customizationHelpersCreateUpdatedCopies() {
        var spec = OverlaySpec.defaults()
                .withSizePreset(OverlaySizePreset.WIDE)
                .withAutoFocus("#passwordField")
                .withCancelAction("#cancelButton")
                .withCloseOnEscape(true);

        assertEquals(OverlaySizePreset.WIDE, spec.sizePreset());
        assertEquals("#passwordField", spec.autoFocusSelector());
        assertEquals("#cancelButton", spec.cancelActionSelector());
        assertTrue(spec.closeOnEscape());
    }
}
