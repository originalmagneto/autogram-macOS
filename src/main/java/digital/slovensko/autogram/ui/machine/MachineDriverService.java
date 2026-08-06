package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import digital.slovensko.autogram.core.DefaultDriverDetector;
import digital.slovensko.autogram.core.DriverDetector;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.cli.CliKeySelector;

import java.time.Instant;
import java.util.Arrays;
import java.util.Date;
import java.util.function.BiFunction;

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
                var certificates = new JsonArray();
                token.getKeys().forEach(key -> certificates.add(certificatePayload(key)));
                var payload = new JsonObject();
                payload.add("certificates", certificates);
                return payload;
            } finally {
                passwordManager.reset();
            }
        } catch (MachineProtocolException exception) {
            throw exception;
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
        return payload;
    }

    private static JsonObject certificatePayload(eu.europa.esig.dss.token.DSSPrivateKeyEntry key) {
        var certificate = key.getCertificate();
        var payload = new JsonObject();
        payload.addProperty("serial", CliKeySelector.serial(key));
        payload.addProperty("commonName", CliKeySelector.commonName(key));
        payload.addProperty("validFrom", timestamp(certificate.getNotBefore()));
        payload.addProperty("validUntil", timestamp(certificate.getNotAfter()));
        payload.addProperty("expired", certificate.getNotAfter().before(new Date()));
        return payload;
    }

    private static String timestamp(Date value) {
        return Instant.ofEpochMilli(value.getTime()).toString();
    }
}
