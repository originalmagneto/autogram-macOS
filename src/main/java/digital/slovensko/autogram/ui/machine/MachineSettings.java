package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.UserSettings;
import eu.europa.esig.dss.enumerations.SignatureLevel;

public final class MachineSettings extends UserSettings {
    public MachineSettings() {
        setCorrectDocumentDisplay(false);
        setBulkEnabled(false);
        setSignatureLevel(SignatureLevel.PAdES_BASELINE_T);
        setTsaEnabled(true);
        setCustomKeystorePath("");
        setCustomPKCS11DriverPath("");
    }
}
