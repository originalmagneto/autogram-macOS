package digital.slovensko.autogram.ui.gui;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FXMLSanityTests {
    private static final Pattern FX_ID_PATTERN = Pattern.compile("fx:id=\"([^\"]+)\"");

    @Test
    void criticalFxmlFilesMustNotContainDuplicateFxIds() throws IOException {
        for (var path : List.of(
                "signing-dialog.fxml",
                "settings-dialog.fxml",
                "password-dialog.fxml",
                "pick-key-dialog.fxml",
                "pick-driver-dialog.fxml",
                "signatures-invalid-dialog.fxml",
                "signatures-not-validated-dialog.fxml",
                "main-menu.fxml")) {
            var content = readGuiResource(path);
            var duplicates = findDuplicateFxIds(content);
            assertTrue(duplicates.isEmpty(),
                    () -> "Duplicate fx:id values in " + path + ": " + duplicates.keySet());
        }
    }

    @Test
    void macosNativeCssMustDefineAccentToken() throws IOException {
        var css = readGuiResource("macos-native.css");
        assertTrue(css.contains("-autogram-accent:"), "macos-native.css is missing -autogram-accent token");
    }

    private static String readGuiResource(String fileName) throws IOException {
        var resourcePath = "/digital/slovensko/autogram/ui/gui/" + fileName;
        var resourceStream = FXMLSanityTests.class.getResourceAsStream(resourcePath);
        assertNotNull(resourceStream, "Missing GUI resource: " + resourcePath);
        return new String(resourceStream.readAllBytes(), StandardCharsets.UTF_8);
    }

    private static Map<String, Integer> findDuplicateFxIds(String content) {
        var counts = new HashMap<String, Integer>();
        Matcher matcher = FX_ID_PATTERN.matcher(content);
        while (matcher.find()) {
            var key = matcher.group(1);
            counts.put(key, counts.getOrDefault(key, 0) + 1);
        }

        var duplicates = new HashMap<String, Integer>();
        for (var entry : counts.entrySet()) {
            if (entry.getValue() > 1) {
                duplicates.put(entry.getKey(), entry.getValue());
            }
        }
        return duplicates;
    }
}
