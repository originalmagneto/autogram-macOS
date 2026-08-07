package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonArray;
import digital.slovensko.autogram.core.DefaultDriverDetector;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.drivers.FakeTokenDriver;
import digital.slovensko.autogram.drivers.TokenDriver;
import eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection;
import eu.europa.esig.dss.token.Pkcs12SignatureToken;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Path;
import java.security.KeyStore;
import java.math.BigInteger;
import java.util.Arrays;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class MachineDriverServiceTest {
    private final MachineProtocolCodec codec = new MachineProtocolCodec();

    @Test
    void capabilitiesForcePdfBaselineTAndQualifiedTimestamp() {
        var service = serviceWith();

        var payload = service.capabilities();

        assertEquals(List.of("PAdES_BASELINE_T"), strings(payload.getAsJsonArray("signatureLevels")));
        var timestampPolicy = payload.getAsJsonObject("timestampPolicy");
        assertTrue(timestampPolicy.get("required").getAsBoolean());
        assertTrue(timestampPolicy.get("qualified").getAsBoolean());
    }

    @Test
    void driversExposeOnlyExpectedMetadata() {
        var driver = new FakeTokenDriver("Test driver", Path.of("fake-driver"), "fake", "");
        var service = serviceWith(driver);

        var payload = service.drivers();

        var listed = payload.getAsJsonArray("drivers").get(0).getAsJsonObject();
        assertEquals("fake", listed.get("id").getAsString());
        assertEquals("Test driver", listed.get("name").getAsString());
        assertEquals("fake-driver", listed.get("path").getAsString());
        assertFalse(listed.get("installed").getAsBoolean());
        assertTrue(listed.has("tokenPresent"));
        assertTrue(listed.get("tokenPresent").isJsonNull());
    }

    @Test
    void certificateResponseDoesNotContainOrRetainPin() {
        var pin = "1234".toCharArray();
        var service = serviceWith(fakeDriver());

        var json = codec.encodeEvent(new MachineEvent(MachineProtocolCodec.VERSION, "certificates.available", "request-1",
                "2026-08-06T00:00:00Z", null, service.certificates("fake", pin)));

        assertFalse(json.contains("1234"));
        assertTrue(Arrays.equals(new char[pin.length], pin));
        var payload = com.google.gson.JsonParser.parseString(json).getAsJsonObject().getAsJsonObject("payload");
        assertTrue(payload.has("tokenKey"));
        assertTrue(payload.getAsJsonArray("certificates").isEmpty());
    }

    @Test
    void certificateDiscoveryUsesOpaqueKeysAndExcludesInvalidCertificates() {
        var valid = key("100", "CN=Jane Doe,O=Example", "CN=Qualified Issuer,O=QTSP", true);
        var expired = key("200", "CN=Jane Doe,O=Example", "CN=Qualified Issuer,O=QTSP", false);

        var payload = MachineDriverService.discoveryPayload("secure_store", "I.CA SecureStore",
                List.of(valid, expired), new Date());

        assertTrue(payload.get("tokenKey").getAsString().startsWith("v1:"));
        assertFalse(payload.toString().contains("CN=Jane Doe"));
        var certificates = payload.getAsJsonArray("certificates");
        assertEquals(1, certificates.size());
        var certificate = certificates.get(0).getAsJsonObject();
        assertEquals("100", certificate.get("serial").getAsString());
        assertEquals("Jane Doe", certificate.get("commonName").getAsString());
        assertEquals("Qualified Issuer", certificate.get("issuer").getAsString());
        assertTrue(certificate.get("certificateKey").getAsString().startsWith("v1:"));
        assertTrue(certificate.get("holderKey").getAsString().startsWith("v1:"));
        assertTrue(certificate.has("validFrom"));
        assertTrue(certificate.has("validUntil"));
    }

    @Test
    void secretUiClearsIssuedCopiesAndRejectsInteractiveSelection() {
        var secretUI = new MachineSecretUI("1234".toCharArray());
        var issuedSecret = secretUI.getKeystorePassword();

        secretUI.close();

        assertTrue(Arrays.equals(new char[issuedSecret.length], issuedSecret));
        assertThrows(UnsupportedOperationException.class,
                () -> secretUI.pickTokenDriverAndThen(List.of(), driver -> { }, () -> { }));
    }

    @Test
    void machineSettingsDoNotExposeBlankCustomDriversAsInstalled() {
        var drivers = new DefaultDriverDetector(new MachineSettings()).getAvailableDrivers();

        assertFalse(drivers.stream().map(TokenDriver::getShortname).anyMatch(id -> id.equals("keystore")
                || id.equals("custom_pkcs11")));
    }

    @Test
    void certificateLifecycleDeliversCachedPinClearsCopiesAndClosesToken() {
        var driver = new RecordingDriver("recording", false);
        var pin = "1234".toCharArray();
        var lifecycle = new PasswordLifecycle();
        var service = lifecycleService(driver, lifecycle);

        service.certificates("recording", pin);

        assertTrue(driver.passwordDelivered);
        assertSame(driver.firstContextPassword, driver.secondContextPassword);
        assertCleared(pin, driver.keystorePassword, driver.firstContextPassword, driver.secondContextPassword);
        assertTrue(driver.token.closed);
        assertTrue(lifecycle.passwordManager.resetCalled);
        assertTrue(lifecycle.passwordManager.resetBeforeUiClosed);
    }

    @Test
    void certificateFailureClearsCachedPinCopiesAndClosesToken() {
        var driver = new RecordingDriver("recording", true);
        var pin = "1234".toCharArray();
        var lifecycle = new PasswordLifecycle();
        var service = lifecycleService(driver, lifecycle);

        assertThrows(MachineProtocolException.class, () -> service.certificates("recording", pin));

        assertTrue(driver.passwordDelivered);
        assertSame(driver.firstContextPassword, driver.secondContextPassword);
        assertCleared(pin, driver.keystorePassword, driver.firstContextPassword, driver.secondContextPassword);
        assertTrue(driver.token.closed);
        assertTrue(lifecycle.passwordManager.resetCalled);
        assertTrue(lifecycle.passwordManager.resetBeforeUiClosed);
    }

    private static MachineDriverService serviceWith(TokenDriver... drivers) {
        return new MachineDriverService(() -> List.of(drivers), new MachineSettings());
    }

    private static MachineDriverService lifecycleService(RecordingDriver driver, PasswordLifecycle lifecycle) {
        return new MachineDriverService(() -> List.of(driver), new MachineSettings(true), lifecycle::create);
    }

    private static FakeTokenDriver fakeDriver() {
        return new FakeTokenDriver("Fake", Path.of("fake"), "fake", "");
    }

    private static eu.europa.esig.dss.token.DSSPrivateKeyEntry key(String serial, String subject,
            String issuer, boolean valid) {
        var entry = mock(eu.europa.esig.dss.token.DSSPrivateKeyEntry.class);
        var certificate = mock(eu.europa.esig.dss.model.x509.CertificateToken.class);
        var subjectPrincipal = mock(eu.europa.esig.dss.model.x509.X500PrincipalHelper.class);
        var issuerPrincipal = mock(eu.europa.esig.dss.model.x509.X500PrincipalHelper.class);
        when(entry.getCertificate()).thenReturn(certificate);
        when(certificate.getSerialNumber()).thenReturn(new BigInteger(serial));
        when(certificate.getEncoded()).thenReturn((serial + subject).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        when(certificate.getSubject()).thenReturn(subjectPrincipal);
        when(subjectPrincipal.getRFC2253()).thenReturn(subject);
        when(certificate.getIssuer()).thenReturn(issuerPrincipal);
        when(issuerPrincipal.getRFC2253()).thenReturn(issuer);
        when(certificate.getNotBefore()).thenReturn(new Date(0));
        when(certificate.getNotAfter()).thenReturn(new Date(Long.MAX_VALUE));
        when(certificate.isValidOn(org.mockito.ArgumentMatchers.any(Date.class))).thenReturn(valid);
        return entry;
    }

    private static List<String> strings(JsonArray values) {
        return values.asList().stream().map(value -> value.getAsString()).toList();
    }

    private static void assertCleared(char[]... values) {
        for (var value : values) {
            assertTrue(Arrays.equals(new char[value.length], value));
        }
    }

    private static final class RecordingDriver extends TokenDriver {
        private final boolean failOnGetKeys;
        private RecordingToken token;
        private char[] keystorePassword;
        private char[] firstContextPassword;
        private char[] secondContextPassword;
        private boolean passwordDelivered;

        private RecordingDriver(String shortname, boolean failOnGetKeys) {
            super("Recording driver", Path.of("/sensitive/driver-path"), shortname, "");
            this.failOnGetKeys = failOnGetKeys;
        }

        @Override
        public AbstractKeyStoreTokenConnection createToken(PasswordManager passwordManager,
                digital.slovensko.autogram.core.SignatureTokenSettings settings) {
            keystorePassword = passwordManager.getPassword();
            passwordDelivered = hasExpectedPin(keystorePassword);
            firstContextPassword = passwordManager.getContextSpecificPassword();
            secondContextPassword = passwordManager.getContextSpecificPassword();
            try {
                token = new RecordingToken(failOnGetKeys);
                return token;
            } catch (IOException exception) {
                throw new RuntimeException(exception);
            }
        }
    }

    private static final class RecordingToken extends Pkcs12SignatureToken {
        private final boolean failOnGetKeys;
        private boolean closed;

        private RecordingToken(boolean failOnGetKeys) throws IOException {
            super(MachineDriverServiceTest.class.getResource("/digital/slovensko/autogram/test.keystore").getFile(),
                    new KeyStore.PasswordProtection(new char[0]));
            this.failOnGetKeys = failOnGetKeys;
        }

        @Override
        public List<eu.europa.esig.dss.token.DSSPrivateKeyEntry> getKeys() {
            if (failOnGetKeys) {
                throw new RuntimeException("token failure");
            }
            return super.getKeys();
        }

        @Override
        public void close() {
            closed = true;
            super.close();
        }
    }

    private static boolean hasExpectedPin(char[] value) {
        return value.length == 4 && value[0] == '1' && value[1] == '2' && value[2] == '3' && value[3] == '4';
    }

    private static final class PasswordLifecycle {
        private RecordingPasswordManager passwordManager;

        private PasswordManager create(MachineSecretUI secretUI, MachineSettings settings) {
            passwordManager = new RecordingPasswordManager(secretUI, settings);
            return passwordManager;
        }
    }

    private static final class RecordingPasswordManager extends PasswordManager {
        private final MachineSecretUI secretUI;
        private boolean resetCalled;
        private boolean resetBeforeUiClosed;

        private RecordingPasswordManager(MachineSecretUI secretUI, MachineSettings settings) {
            super(secretUI, settings);
            this.secretUI = secretUI;
        }

        @Override
        public void reset() {
            resetCalled = true;
            resetBeforeUiClosed = !secretUI.isClosed();
            super.reset();
        }
    }
}
