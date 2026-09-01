package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.UserSettings;
import eu.europa.esig.dss.enumerations.SignatureLevel;

import java.nio.file.Path;
import java.util.List;
import java.util.UUID;

/**
 * Machine mode in the bundled engine ignores UserSettings slot mappings.
 * I.CA SecureStore exposes an empty reader at index 0 and the card at index 1.
 */
public final class MachineSettings extends UserSettings {
    private final String disabledKeystorePath;
    private final String disabledPkcs11DriverPath;
    private final List<String> trustedList;

    public MachineSettings() {
        this(false);
    }

    MachineSettings(boolean bulkEnabled) {
        super();
        this.disabledKeystorePath = disabledPath("keystore");
        this.disabledPkcs11DriverPath = disabledPath("pkcs11");
        var loaded = UserSettings.load();
        this.trustedList = List.copyOf(loaded.getTrustedList());
        var secureStoreSlot = loaded.getDriverSlotIndex("secure_store");
        setDriverSlotIndex("secure_store", secureStoreSlot >= 0 ? secureStoreSlot : 1);
        setCorrectDocumentDisplay(false);
        setBulkEnabled(bulkEnabled);
        setSignatureLevel(SignatureLevel.PAdES_BASELINE_T);
        setTsaEnabled(true);
    }

    public String getCustomKeystorePath() {
        return disabledKeystorePath;
    }

    public String getCustomPKCS11DriverPath() {
        return disabledPkcs11DriverPath;
    }

    public List<String> getTrustedList() {
        return trustedList;
    }

    private static String disabledPath(String kind) {
        return Path.of(System.getProperty("java.io.tmpdir"),
                "autogram-machine-disabled-" + kind + "-" + UUID.randomUUID()).toString();
    }
}
