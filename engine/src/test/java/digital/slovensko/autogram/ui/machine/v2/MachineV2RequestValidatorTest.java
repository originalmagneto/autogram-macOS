package digital.slovensko.autogram.ui.machine.v2;

import com.google.gson.JsonParser;
import digital.slovensko.autogram.ui.machine.MachineProtocolException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class MachineV2RequestValidatorTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void acceptsXadesBaselineBWithoutTimestampForAnAsicEnvelope() throws Exception {
        var envelope = Files.write(temporaryDirectory.resolve("kontajner.asice"), new byte[] { 'P', 'K', 3, 4 })
                .toRealPath();

        assertDoesNotThrow(() -> MachineV2RequestValidator.validateSign(signPayload("XAdES_BASELINE_B", envelope)));
    }

    @Test
    void keepsRejectingBaselineBForAPlainPdf() throws Exception {
        var pdf = Files.writeString(temporaryDirectory.resolve("source.pdf"), "%PDF-1.7\n%%EOF").toRealPath();

        assertThrows(MachineProtocolException.class,
                () -> MachineV2RequestValidator.validateSign(signPayload("XAdES_BASELINE_B", pdf)));
        assertThrows(MachineProtocolException.class,
                () -> MachineV2RequestValidator.validateSign(signPayload("PAdES_BASELINE_B", pdf)));
    }

    private com.google.gson.JsonObject signPayload(String level, Path source) throws Exception {
        var target = temporaryDirectory.toRealPath().resolve("signed.out");
        return JsonParser.parseString("""
                {"driver":"fake","certificateSerial":"123","pin":"1234","signatureLevel":"%s",
                 "timestamp":{"required":false,"servers":[]},
                 "files":[{"id":"one","source":"%s","target":"%s"}]}
                """.formatted(level, source, target)).getAsJsonObject();
    }
}
