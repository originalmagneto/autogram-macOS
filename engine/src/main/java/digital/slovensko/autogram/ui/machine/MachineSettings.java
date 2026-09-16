package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.UserSettings;
import eu.europa.esig.dss.enumerations.SignatureLevel;

import java.nio.file.Path;
import java.util.List;
import java.util.UUID;

public final class MachineSettings extends UserSettings {
    private static final String SECURE_STORE_DRIVER = "secure_store";
    /** I.CA SecureStore exposes an empty reader at slot index 0 and the card at index 1. */
    private static final int SECURE_STORE_CARD_SLOT_INDEX = 1;

    private final String disabledKeystorePath = disabledPath("keystore");
    private final String disabledPkcs11DriverPath = disabledPath("pkcs11");
    private final List<String> trustedList;
    private EFormRequest eform;

    public EFormRequest getEform() {
        return eform;
    }

    public void setEform(EFormRequest eform) {
        this.eform = eform;
    }

    public MachineSettings() {
        this(false);
    }

    MachineSettings(boolean cacheContextSpecificPassword) {
        // Machine mode ignores the GUI slot mappings except an explicit SecureStore slot.
        var loaded = UserSettings.load();
        trustedList = List.copyOf(loaded.getTrustedList());
        setDriverSlotIndex(SECURE_STORE_DRIVER, secureStoreSlotIndex(loaded.getDriverSlotIndex(SECURE_STORE_DRIVER)));
        setCorrectDocumentDisplay(false);
        setBulkEnabled(cacheContextSpecificPassword);
        setSignatureLevel(SignatureLevel.PAdES_BASELINE_T);
        setTsaEnabled(true);
    }

    /**
     * UserSettings forces a context-specific login whenever bulk mode is on, and the
     * machine session runs in bulk mode to reuse the PIN across files. On a token
     * with CKF_PROTECTED_AUTHENTICATION_PATH (the eID) that sent the PIN from the
     * app to the card as the BOK, where a wrong value spends an attempt. Without the
     * force, such a token asks for the BOK in the eID client's own window, as the
     * official Autogram does; tokens without that flag still log in with the PIN.
     */
    @Override
    public boolean getForceContextSpecificLoginEnabled() {
        return false;
    }

    @Override
    public String getCustomKeystorePath() {
        return disabledKeystorePath;
    }

    @Override
    public String getCustomPKCS11DriverPath() {
        return disabledPkcs11DriverPath;
    }

    @Override
    public List<String> getTrustedList() {
        return trustedList;
    }

    static int secureStoreSlotIndex(int configuredSlotIndex) {
        return configuredSlotIndex >= 0 ? configuredSlotIndex : SECURE_STORE_CARD_SLOT_INDEX;
    }

    private static String disabledPath(String kind) {
        return Path.of(System.getProperty("java.io.tmpdir"), "autogram-machine-disabled-" + kind + "-" + UUID.randomUUID())
                .toString();
    }
}
