package digital.slovensko.autogram.ui.gui;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertIterableEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UpdateControllerTests {
    @Test
    void isSecurityReleaseDetectsSecurityKeywordsCaseInsensitively() {
        assertTrue(UpdateController.isSecurityRelease("[WARNING]\nThis is a security patch release, please upgrade."));
        assertTrue(UpdateController.isSecurityRelease("Critical fix for updater stability."));
        assertFalse(UpdateController.isSecurityRelease("Improved onboarding and visual polish."));
    }

    @Test
    void extractReleaseHighlightsNormalizesMarkdownAndDeduplicatesEntries() {
        var releaseNotes = """
                [WARNING]
                - `Security` patch for updater
                - Faster startup for PDF preview
                - Faster startup for PDF preview

                > Better signing flow for certificates
                """;

        assertIterableEquals(List.of(
                        "Security patch for updater",
                        "Faster startup for PDF preview",
                        "Better signing flow for certificates"),
                UpdateController.extractReleaseHighlights(releaseNotes));
    }

    @Test
    void extractReleaseHighlightsFallsBackForBlankInput() {
        assertEquals(
                List.of("Vylepšenia stability, kompatibility a používateľského zážitku."),
                UpdateController.extractReleaseHighlights("   "));
    }
}
