package digital.slovensko.autogram.ui.machine.v2;

import com.google.gson.JsonParser;
import digital.slovensko.autogram.ui.machine.MachineDriverService;
import digital.slovensko.autogram.ui.machine.MachineInspectionService;
import org.apache.commons.cli.DefaultParser;
import org.apache.commons.cli.Options;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.PrintWriter;
import java.io.StringReader;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class MachineV2CliAppTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void completesCapabilitiesAndInspectionOnceForEachRequestId() throws Exception {
        var source = Files.writeString(temporaryDirectory.resolve("source.pdf"), "%PDF-1.7\n%%EOF").toRealPath();
        var target = temporaryDirectory.resolve("signed.pdf");
        var input = "{\"protocolVersion\":2,\"requestId\":\"capabilities-1\",\"operation\":\"CAPABILITIES\",\"payload\":{}}\n"
                + "{\"protocolVersion\":2,\"requestId\":\"inspect-1\",\"operation\":\"INSPECT\",\"payload\":{\"files\":[{\"id\":\"file-1\",\"source\":\""
                + source + "\",\"target\":\"" + target + "\"}]}}\n"
                + "{\"protocolVersion\":2,\"requestId\":\"inspect-invalid\",\"operation\":\"INSPECT\",\"payload\":{\"unexpected\":true}}\n";
        var output = new StringWriter();
        var code = MachineV2CliApp.start(commandLine(), new StringReader(input), new PrintWriter(output),
                new PrintWriter(new StringWriter()), new MachineDriverService(), new MachineInspectionService());

        var events = Arrays.stream(output.toString().strip().split("\\n"))
                .map(JsonParser::parseString)
                .map(element -> element.getAsJsonObject())
                .toList();
        var terminalEvents = events.stream()
                .filter(event -> List.of("request.completed", "request.failed").contains(event.get("type").getAsString()))
                .toList();

        assertEquals(0, code);
        assertEquals(List.of("capabilities-1", "inspect-1", "inspect-invalid"), terminalEvents.stream()
                .map(event -> event.get("requestId").getAsString()).toList());
        assertEquals(1, terminalEvents.stream()
                .filter(event -> "capabilities-1".equals(event.get("requestId").getAsString())).count());
        assertEquals(1, terminalEvents.stream()
                .filter(event -> "inspect-1".equals(event.get("requestId").getAsString())).count());
        assertEquals("PROTOCOL_INVALID_REQUEST", terminalEvents.get(2).getAsJsonObject("payload").get("code").getAsString());
    }

    @Test
    void previewsEmbeddedAsicDocumentAndRedactsSourceForUnknownName() throws Exception {
        var source = Path.of(MachineV2CliAppTest.class
                .getResource("/digital/slovensko/autogram/sample_pdf_xades.asice").getFile());
        var expectedPdf = Files.readAllBytes(Path.of(MachineV2CliAppTest.class
                .getResource("/digital/slovensko/autogram/sample.pdf").getFile()));
        var input = "{\"protocolVersion\":2,\"requestId\":\"preview-1\",\"operation\":\"PREVIEW\",\"payload\":{\"source\":\""
                + source + "\",\"document\":\"sample.pdf\"}}\n"
                + "{\"protocolVersion\":2,\"requestId\":\"preview-missing\",\"operation\":\"PREVIEW\",\"payload\":{\"source\":\""
                + source + "\",\"document\":\"missing.pdf\"}}\n";
        var output = new StringWriter();

        var code = MachineV2CliApp.start(commandLine(), new StringReader(input), new PrintWriter(output),
                new PrintWriter(new StringWriter()), new MachineDriverService(), new MachineInspectionService());

        var events = Arrays.stream(output.toString().strip().split("\\n"))
                .map(JsonParser::parseString)
                .map(element -> element.getAsJsonObject())
                .toList();
        var preview = events.stream()
                .filter(event -> "preview.completed".equals(event.get("type").getAsString()))
                .findFirst()
                .orElseThrow();

        assertEquals(0, code);
        assertEquals(List.of("request.started", "preview.completed", "request.completed", "request.started", "request.failed"),
                events.stream().map(event -> event.get("type").getAsString()).toList());
        assertEquals("sample.pdf", preview.getAsJsonObject("payload").get("name").getAsString());
        assertEquals("application/pdf", preview.getAsJsonObject("payload").get("mediaType").getAsString());
        assertArrayEquals(expectedPdf, Base64.getDecoder().decode(
                preview.getAsJsonObject("payload").get("contentBase64").getAsString()));
        assertEquals("PREVIEW_DOCUMENT_NOT_FOUND", events.get(4).getAsJsonObject("payload").get("code").getAsString());
        assertFalse(output.toString().contains(source.toString()));
    }

    private static org.apache.commons.cli.CommandLine commandLine() throws Exception {
        var options = new Options()
                .addOption(null, "machine-readable", false, "")
                .addOption(null, "protocol-version", true, "");
        return new DefaultParser().parse(options, new String[] { "--machine-readable", "--protocol-version", "2" });
    }
}
