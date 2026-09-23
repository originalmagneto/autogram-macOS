package digital.slovensko.autogram.core;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DefaultDriverDetectorOpenSCTest {
    @Test
    void openscInstallerPathComesFirst() {
        assertEquals(Path.of("/Library/OpenSC/lib/opensc-pkcs11.so"),
                DefaultDriverDetector.OPENSC_MAC_MODULE_PATHS.get(0));
        assertEquals("opensc", DefaultDriverDetector.TokenDriverShortnames.OPENSC);
    }

    @Test
    void openscModulePathIsAnInstalledCandidateOrTheInstallerDefault() {
        var path = DefaultDriverDetector.openscMacModulePath();

        assertTrue(DefaultDriverDetector.OPENSC_MAC_MODULE_PATHS.contains(path));
        var installed = DefaultDriverDetector.OPENSC_MAC_MODULE_PATHS.stream().filter(Files::exists).findFirst();
        assertEquals(installed.orElse(DefaultDriverDetector.OPENSC_MAC_MODULE_PATHS.get(0)), path);
    }
}
