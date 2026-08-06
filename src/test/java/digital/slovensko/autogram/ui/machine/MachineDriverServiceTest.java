package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonArray;
import digital.slovensko.autogram.drivers.FakeTokenDriver;
import digital.slovensko.autogram.drivers.TokenDriver;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
    }

    @Test
    void certificateResponseDoesNotContainOrRetainPin() {
        var pin = "1234".toCharArray();
        var service = serviceWith(fakeDriver());

        var json = codec.encodeEvent(new MachineEvent(MachineProtocolCodec.VERSION, "certificates.available", "request-1",
                "2026-08-06T00:00:00Z", null, service.certificates("fake", pin)));

        assertFalse(json.contains("1234"));
        assertTrue(Arrays.equals(new char[pin.length], pin));
        var certificate = com.google.gson.JsonParser.parseString(json).getAsJsonObject()
                .getAsJsonObject("payload").getAsJsonArray("certificates").get(0).getAsJsonObject();
        assertTrue(certificate.has("serial"));
        assertTrue(certificate.has("commonName"));
        assertTrue(certificate.has("validFrom"));
        assertTrue(certificate.has("validUntil"));
        assertTrue(certificate.has("expired"));
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

    private static MachineDriverService serviceWith(TokenDriver... drivers) {
        return new MachineDriverService(() -> List.of(drivers), new MachineSettings());
    }

    private static FakeTokenDriver fakeDriver() {
        return new FakeTokenDriver("Fake", Path.of("fake"), "fake", "");
    }

    private static List<String> strings(JsonArray values) {
        return values.asList().stream().map(value -> value.getAsString()).toList();
    }
}
