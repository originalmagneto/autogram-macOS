package digital.slovensko.autogram.core;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PdfaNormalizeTest {
    private static final String ICC = "/System/Library/ColorSync/Profiles/sRGB Profile.icc";

    @TempDir
    Path temporaryDirectory;

    private Path sample() {
        return Path.of(PdfaNormalizeTest.class
                .getResource("/digital/slovensko/autogram/sample.pdf").getFile());
    }

    private String normalizedText(Path source) throws Exception {
        var output = temporaryDirectory.resolve("normalized-" + System.nanoTime() + ".pdf");
        PdfaNormalize.normalize(source.toFile(), output.toFile(), new File(ICC), "Test");
        return new String(Files.readAllBytes(output), StandardCharsets.ISO_8859_1);
    }

    @Test
    void writesThePdfaIdentificationTheValidatorsLookFor() throws Exception {
        var text = normalizedText(sample());

        assertTrue(text.startsWith("%PDF-"), "must stay a PDF");
        assertTrue(text.contains("pdfaid:part=\"2\""), "PDF/A part, attribute form");
        assertTrue(text.contains("pdfaid:conformance=\"B\""), "PDF/A conformance, attribute form");
        assertTrue(text.contains("%%EOF"));
        assertTrue(text.contains("startxref"));
    }

    @Test
    void embedsTheOutputIntentWithAnIccProfile() throws Exception {
        var text = normalizedText(sample());

        assertTrue(text.contains("OutputIntent"));
        assertTrue(text.contains("GTS_PDFA"));
        assertTrue(text.contains("DestOutputProfile"));
    }

    /**
     * The whole reason this class exists. Everything downstream reads the catalog
     * by scanning bytes, and an object stream would hide /OutputIntents, /AF and
     * /AFRelationship from that scan.
     */
    @Test
    void writesWithoutObjectStreamsSoTheCatalogStaysReadable() throws Exception {
        var text = normalizedText(sample());

        assertFalse(text.contains("ObjStm"), "object streams would hide the catalog from byte scans");
    }

    /**
     * Mirrors what the app does: the osvedčovacia doložka is attached as an
     * incremental update, so the source arrives with two cross-reference tables
     * and stale metadata. Normalizing must leave exactly one of each.
     */
    @Test
    void collapsesAnIncrementallyUpdatedFileIntoOneCrossReferenceTable() throws Exception {
        var original = Files.readAllBytes(sample());
        var incremental = temporaryDirectory.resolve("incremental.pdf");
        var appended = new String(original, StandardCharsets.ISO_8859_1)
                + "\n% incremental update\n1 0 obj\n<< /Type /Catalog >>\nendobj\nstartxref\n0\n%%EOF\n";
        Files.write(incremental, appended.getBytes(StandardCharsets.ISO_8859_1));
        assertEquals(2, countOf(appended, "%%EOF"), "the fixture must really be incrementally updated");

        var text = normalizedText(incremental);

        assertEquals(1, countOf(text, "%%EOF"), "one end marker after normalizing");
        assertEquals(1, countOf(text, "startxref"), "one cross-reference table after normalizing");
    }

    private static int countOf(String haystack, String needle) {
        int count = 0;
        int index = haystack.indexOf(needle);
        while (index >= 0) {
            count++;
            index = haystack.indexOf(needle, index + needle.length());
        }
        return count;
    }
}
