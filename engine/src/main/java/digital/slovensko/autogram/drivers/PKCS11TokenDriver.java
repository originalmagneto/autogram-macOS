package digital.slovensko.autogram.drivers;

import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.core.SignatureTokenSettings;
import eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection;
import eu.europa.esig.dss.token.PrefilledPasswordCallback;

import java.nio.file.Path;
import java.security.KeyStore;

public class PKCS11TokenDriver extends TokenDriver {
    public PKCS11TokenDriver(String name, Path path, String shortname, String noKeysHelperText) {
        super(name, path, shortname, noKeysHelperText);
    }

    public AbstractKeyStoreTokenConnection createToken(PasswordManager pm, SignatureTokenSettings settings) {
        var probed = PKCS11TokenPresenceProbe.firstTokenSlotIndex(getPath());
        int slotIndex;
        if (probed.isPresent()) {
            slotIndex = probed.getAsInt();
        } else {
            var configured = settings.getDriverSlotIndex(getShortname());
            slotIndex = configured >= 0 ? configured
                    : "secure_store".equals(getShortname()) ? 1 : -1;
        }
        return new NativePkcs11SignatureToken(getPath().toString(), pm, settings, slotIndex);
    }

    @Override
    public Boolean tokenPresent() {
        return PKCS11TokenPresenceProbe.tokenPresent(getPath()).orElse(null);
    }
}
