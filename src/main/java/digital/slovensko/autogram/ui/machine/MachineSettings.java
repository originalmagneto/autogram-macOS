package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.UserSettings;
import eu.europa.esig.dss.enumerations.SignatureLevel;

import java.nio.file.Path;
import java.util.UUID;

public final class MachineSettings extends UserSettings {
    private final String disabledKeystorePath = disabledPath("keystore");
    private final String disabledPkcs11DriverPath = disabledPath("pkcs11");

    public MachineSettings() {
        this(false);
    }

    MachineSettings(boolean cacheContextSpecificPassword) {
        setCorrectDocumentDisplay(false);
        setBulkEnabled(cacheContextSpecificPassword);
        setSignatureLevel(SignatureLevel.PAdES_BASELINE_T);
        setTsaEnabled(true);
    }

    @Override
    public String getCustomKeystorePath() {
        return disabledKeystorePath;
    }

    @Override
    public String getCustomPKCS11DriverPath() {
        return disabledPkcs11DriverPath;
    }

    private static String disabledPath(String kind) {
        return Path.of(System.getProperty("java.io.tmpdir"), "autogram-machine-disabled-" + kind + "-" + UUID.randomUUID())
                .toString();
    }
}
