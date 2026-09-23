package digital.slovensko.autogram.core;

import digital.slovensko.autogram.drivers.FakeTokenDriver;
import digital.slovensko.autogram.drivers.PKCS11TokenDriver;
import digital.slovensko.autogram.drivers.PKCS12KeystoreTokenDriver;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.util.OperatingSystem;

import java.nio.file.Path;
import java.util.List;

public class DefaultDriverDetector implements DriverDetector {
    private final DriverDetectorSettings settings;

    public static class TokenDriverShortnames {
        public static final String EID = "eid";
        public static final String CZ_EID = "cz_eid";
        public static final String SECURE_STORE = "secure_store";
        public static final String MONET = "monet";
        public static final String GEMALTO = "gemalto";
        public static final String FAKE = "fake";
        public static final String KEYSTORE = "keystore";
        public static final String CUSTOM_PKCS11 = "custom_pkcs11";
        public static final String OPENSC = "opensc";
    }

    /**
     * Where the OpenSC installer (DMG, /Library/OpenSC) and Homebrew put the OpenSC
     * PKCS#11 module. The first one present wins; without either, the driver stays
     * uninstalled and is never offered.
     */
    static final List<Path> OPENSC_MAC_MODULE_PATHS = List.of(
            Path.of("/Library/OpenSC/lib/opensc-pkcs11.so"),
            Path.of("/opt/homebrew/lib/opensc-pkcs11.so"),
            Path.of("/usr/local/lib/opensc-pkcs11.so"));

    // FIXME use i18n
    private final String HELPER_TEXT_EID = "\n\nV prípade nového občianskeho preukazu to môže znamenať, že si potrebujete certifikáty na podpisovanie cez občiansky preukaz vydať. Robí sa to pomocou obslužného softvéru eID klient.";
    private final String HELPER_TEXT_CZ_EID = "";
    private final String HELPER_TEXT_SECURE_STORE = "";
    private final String HELPER_TEXT_MONET = "";
    private final String HELPER_TEXT_GEMALTO = "\n\nV prípade kvalifikovaných certifikátov na karte Gemalto ID Prime 940 môže byť potrebné nastaviť slot index 8. Skúste nastavenia -> Iné -> Slot index";
    private final String HELPER_TEXT_FAKE = "";
    private final String HELPER_TEXT_KEYSTORE = "";
    private final String HELPER_TEXT_CUSTOM_PKCS11_DRIVER = "";
    private final String HELPER_TEXT_OPENSC = "\n\nOpenSC je open-source ovládač. Občiansky preukaz podporuje iba v kontaktnej čítačke a zatiaľ nie je overený pre kvalifikovaný podpis v tejto aplikácii.";

    public DefaultDriverDetector(DriverDetectorSettings settings) {
        this.settings = settings;
    }

    // FIXME use i18n
    private List<TokenDriver> getLinuxDrivers(){
        return List.of(
            new PKCS11TokenDriver("Občiansky preukaz (eID klient)", Path.of("/usr/lib/eID_klient/libpkcs11_x64.so"), TokenDriverShortnames.EID, HELPER_TEXT_EID),
            new PKCS11TokenDriver("Občiansky preukaz (starý eID klient)", Path.of("/usr/lib/eac_mw_klient/libpkcs11_x64.so"), TokenDriverShortnames.EID, HELPER_TEXT_EID),
            new PKCS11TokenDriver("eObčanka", Path.of("/usr/lib/x86_64-linux-gnu/libeopproxy11.so"), TokenDriverShortnames.CZ_EID, HELPER_TEXT_CZ_EID),
            new PKCS11TokenDriver("I.CA SecureStore", Path.of("/usr/lib/pkcs11/libICASecureStorePkcs11.so"), TokenDriverShortnames.SECURE_STORE, HELPER_TEXT_SECURE_STORE),
            new PKCS11TokenDriver("MONET+ ProID+Q", Path.of("/usr/lib/x86_64-linux-gnu/libproidqcm11.so"), TokenDriverShortnames.MONET, HELPER_TEXT_MONET),
            new PKCS11TokenDriver("Gemalto IDPrime 940", Path.of("/usr/lib/libIDPrimePKCS11.so"), TokenDriverShortnames.GEMALTO, HELPER_TEXT_GEMALTO),
            new PKCS12KeystoreTokenDriver("Zo súboru", Path.of(settings.getCustomKeystorePath()), TokenDriverShortnames.KEYSTORE, HELPER_TEXT_KEYSTORE),
            new FakeTokenDriver("Fake token driver",  Path.of("fakeTokenDriver"), TokenDriverShortnames.FAKE, HELPER_TEXT_FAKE),
            new PKCS11TokenDriver("Vlastný ovládač pre PKCS11 Token", Path.of(settings.getCustomPKCS11DriverPath()), TokenDriverShortnames.CUSTOM_PKCS11, HELPER_TEXT_CUSTOM_PKCS11_DRIVER)
        );
    }

    private List<TokenDriver> getWindowsDrivers() {
        return List.of(
            new PKCS11TokenDriver("Občiansky preukaz (eID klient)", Path.of("C:\\Program Files (x86)\\eID_klient\\pkcs11_x64.dll"), TokenDriverShortnames.EID, HELPER_TEXT_EID),
            new PKCS11TokenDriver("Občiansky preukaz (eID klient)", Path.of("C:\\Program Files\\eID_klient\\pkcs11_x64.dll"), TokenDriverShortnames.EID, HELPER_TEXT_EID),
            new PKCS11TokenDriver("eObčanka", Path.of("C:\\Windows\\System32\\eopproxyp11.dll"), TokenDriverShortnames.CZ_EID, HELPER_TEXT_CZ_EID),
            new PKCS11TokenDriver("I.CA SecureStore", Path.of("C:\\Windows\\System32\\SecureStorePkcs11.dll"), TokenDriverShortnames.SECURE_STORE, HELPER_TEXT_SECURE_STORE),
            new PKCS11TokenDriver("MONET+ ProID+Q", Path.of( "C:\\Windows\\system32\\proidqcm11.dll"), TokenDriverShortnames.MONET, HELPER_TEXT_MONET),
            new PKCS11TokenDriver("Gemalto IDPrime 940", Path.of("C:\\Windows\\System32\\eTPKCS11.dll"), TokenDriverShortnames.GEMALTO, HELPER_TEXT_GEMALTO),
            new PKCS12KeystoreTokenDriver("Zo súboru", Path.of(settings.getCustomKeystorePath()), TokenDriverShortnames.KEYSTORE, HELPER_TEXT_KEYSTORE),
            new FakeTokenDriver("Fake token driver",  Path.of("fakeTokenDriver"), TokenDriverShortnames.FAKE, HELPER_TEXT_FAKE),
            new PKCS11TokenDriver("Vlastný ovládač pre PKCS11 Token", Path.of(settings.getCustomPKCS11DriverPath()), TokenDriverShortnames.CUSTOM_PKCS11, HELPER_TEXT_CUSTOM_PKCS11_DRIVER)
        );
    }

    private List<TokenDriver> getMacDrivers() {
        return List.of(
            new PKCS11TokenDriver("Občiansky preukaz (eID klient)", Path.of("/Applications/eID_klient.app/Contents/Frameworks/libPkcs11.dylib"), TokenDriverShortnames.EID, HELPER_TEXT_EID),
            new PKCS11TokenDriver("eObčanka", Path.of("/usr/local/lib/eOPCZE/libeopproxyp11.dylib"), TokenDriverShortnames.CZ_EID, HELPER_TEXT_CZ_EID),
            new PKCS11TokenDriver("I.CA SecureStore", Path.of("/usr/local/lib/pkcs11/libICASecureStorePkcs11.dylib"), TokenDriverShortnames.SECURE_STORE, HELPER_TEXT_SECURE_STORE),
            new PKCS11TokenDriver("MONET+ ProID+Q", Path.of("/usr/local/lib/ProIDPlus/libproidqcm11.dylib"), TokenDriverShortnames.MONET, HELPER_TEXT_MONET),
            new PKCS11TokenDriver("Gemalto IDPrime 940", Path.of("/usr/local/lib/libIDPrimePKCS11.dylib"), TokenDriverShortnames.GEMALTO, HELPER_TEXT_GEMALTO),
            // After the vendor drivers: the app prefers the eID client for an eID card and
            // falls back to the first other driver with a token, so OpenSC only signs when
            // no vendor middleware claims the card.
            new PKCS11TokenDriver("OpenSC", openscMacModulePath(), TokenDriverShortnames.OPENSC, HELPER_TEXT_OPENSC),
            new PKCS12KeystoreTokenDriver("Zo súboru", Path.of(settings.getCustomKeystorePath()), TokenDriverShortnames.KEYSTORE, HELPER_TEXT_KEYSTORE),
            new FakeTokenDriver("Fake token driver",  Path.of("fakeTokenDriver"), TokenDriverShortnames.FAKE, HELPER_TEXT_FAKE),
            new PKCS11TokenDriver("Vlastný ovládač pre PKCS11 Token", Path.of(settings.getCustomPKCS11DriverPath()), TokenDriverShortnames.CUSTOM_PKCS11, HELPER_TEXT_CUSTOM_PKCS11_DRIVER)
        );
    }

    static Path openscMacModulePath() {
        return OPENSC_MAC_MODULE_PATHS.stream()
                .filter(java.nio.file.Files::exists)
                .findFirst()
                .orElse(OPENSC_MAC_MODULE_PATHS.get(0));
    }

    public List<TokenDriver> getAvailableDrivers() {
        return getAllDrivers().stream().filter(TokenDriver::isInstalled).toList();
    }

    private List<TokenDriver> getAllDrivers() {
        switch (OperatingSystem.current()) {
            case WINDOWS -> {
                return getWindowsDrivers();
            }
            case LINUX -> {
                return getLinuxDrivers();
            }
            case MAC -> {
                return getMacDrivers();
            }
            default -> throw new IllegalStateException("Unexpected value: " + OperatingSystem.current());
        }
    }
}
