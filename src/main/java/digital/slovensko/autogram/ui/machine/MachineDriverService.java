package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import digital.slovensko.autogram.core.DefaultDriverDetector;
import digital.slovensko.autogram.core.DriverDetector;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.core.errors.AutogramException;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.cli.CliKeySelector;
import eu.europa.esig.dss.model.DSSException;

import java.time.Instant;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Date;
import java.util.HexFormat;
import java.util.List;
import java.util.function.BiFunction;
import javax.security.auth.x500.X500Principal;

public final class MachineDriverService {
    private final DriverDetector driverDetector;
    private final MachineSettings settings;
    private final BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory;

    public MachineDriverService() {
        this(new MachineSettings());
    }

    private MachineDriverService(MachineSettings settings) {
        this(new DefaultDriverDetector(settings), settings);
    }

    MachineDriverService(DriverDetector driverDetector, MachineSettings settings) {
        this(driverDetector, settings, PasswordManager::new);
    }

    MachineDriverService(DriverDetector driverDetector, MachineSettings settings,
            BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory) {
        this.driverDetector = driverDetector;
        this.settings = settings;
        this.passwordManagerFactory = passwordManagerFactory;
    }

    public JsonObject capabilities() {
        var payload = new JsonObject();
        var signatureLevels = new JsonArray();
        signatureLevels.add("PAdES_BASELINE_T");
        payload.add("signatureLevels", signatureLevels);

        var timestampPolicy = new JsonObject();
        timestampPolicy.addProperty("required", true);
        timestampPolicy.addProperty("qualified", true);
        payload.add("timestampPolicy", timestampPolicy);
        return payload;
    }

    public JsonObject drivers() {
        var drivers = new JsonArray();
        driverDetector.getAvailableDrivers().forEach(driver -> drivers.add(driverPayload(driver)));
        var payload = new JsonObject();
        payload.add("drivers", drivers);
        return payload;
    }

    public JsonObject certificates(String driverId, char[] pin) {
        try {
            var driver = driverDetector.getAvailableDrivers().stream()
                    .filter(candidate -> candidate.getShortname().equals(driverId))
                    .findFirst()
                    .orElseThrow(() -> new MachineProtocolException("DRIVER_NOT_FOUND"));
            return certificates(driver, pin);
        } finally {
            Arrays.fill(pin, '\0');
        }
    }

    private JsonObject certificates(TokenDriver driver, char[] pin) {
        try (var secretUI = new MachineSecretUI(pin)) {
            var passwordManager = passwordManagerFactory.apply(secretUI, settings);
            try (var token = driver.createToken(passwordManager, settings)) {
                return discoveryPayload(driver.getShortname(), driver.getName(), token.getKeys(), new Date());
            } finally {
                passwordManager.reset();
            }
        } catch (MachineProtocolException exception) {
            throw exception;
        } catch (DSSException exception) {
            throw AutogramException.createFromDSSException(exception);
        } catch (Exception exception) {
            throw new MachineProtocolException("DRIVER_UNAVAILABLE", exception);
        }
    }

    private static JsonObject driverPayload(TokenDriver driver) {
        var payload = new JsonObject();
        payload.addProperty("id", driver.getShortname());
        payload.addProperty("name", driver.getName());
        payload.addProperty("path", driver.getPath().toString());
        payload.addProperty("installed", driver.isInstalled());
        var tokenPresent = driver.tokenPresent();
        if (tokenPresent == null) {
            payload.add("tokenPresent", com.google.gson.JsonNull.INSTANCE);
        } else {
            payload.addProperty("tokenPresent", tokenPresent);
        }
        return payload;
    }

    static JsonObject discoveryPayload(String providerId, String providerName,
            List<eu.europa.esig.dss.token.DSSPrivateKeyEntry> keys, Date now) {
        var eligible = keys.stream().filter(key -> key.getCertificate().isValidOn(now)).toList();
        var holderIdentities = eligible.stream()
                .map(key -> normalizedSubject(key.getCertificate()))
                .distinct()
                .sorted()
                .toList();
        var payload = new JsonObject();
        payload.addProperty("tokenKey", holderIdentities.isEmpty()
                ? opaqueKey("token", providerId)
                : opaqueKey("token", providerId, String.join("\u0000", holderIdentities)));
        payload.addProperty("providerName", providerName);
        var certificates = new JsonArray();
        eligible.forEach(key -> certificates.add(certificatePayload(key)));
        payload.add("certificates", certificates);
        return payload;
    }

    private static JsonObject certificatePayload(eu.europa.esig.dss.token.DSSPrivateKeyEntry key) {
        var certificate = key.getCertificate();
        var payload = new JsonObject();
        payload.addProperty("serial", CliKeySelector.serial(key));
        payload.addProperty("commonName", CliKeySelector.commonName(key));
        payload.addProperty("issuer", certificate.getIssuer() == null ? "Unknown issuer"
                : digital.slovensko.autogram.util.DSSUtils.parseCN(certificate.getIssuer().getRFC2253()));
        payload.addProperty("validFrom", timestamp(certificate.getNotBefore()));
        payload.addProperty("validUntil", timestamp(certificate.getNotAfter()));
        payload.addProperty("certificateKey", opaqueKey("certificate", certificate.getEncoded()));
        payload.addProperty("holderKey", opaqueKey("holder", normalizedSubject(certificate)));
        return payload;
    }

    private static String normalizedSubject(eu.europa.esig.dss.model.x509.CertificateToken certificate) {
        return new X500Principal(certificate.getSubject().getRFC2253()).getName(X500Principal.CANONICAL);
    }

    private static String opaqueKey(String domain, String... values) {
        var digest = digest(domain);
        for (var value : values) {
            digest.update((byte) 0);
            digest.update(value.getBytes(StandardCharsets.UTF_8));
        }
        return "v1:" + HexFormat.of().formatHex(digest.digest());
    }

    private static String opaqueKey(String domain, byte[] value) {
        var digest = digest(domain);
        digest.update((byte) 0);
        digest.update(value);
        return "v1:" + HexFormat.of().formatHex(digest.digest());
    }

    private static MessageDigest digest(String domain) {
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            digest.update(domain.getBytes(StandardCharsets.UTF_8));
            return digest;
        } catch (NoSuchAlgorithmException exception) {
            throw new AssertionError("SHA-256 is required", exception);
        }
    }

    private static String timestamp(Date value) {
        return Instant.ofEpochMilli(value.getTime()).toString();
    }
}
