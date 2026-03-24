package digital.slovensko.autogram.util;

import org.junit.jupiter.api.Test;
import org.xml.sax.InputSource;

import javax.xml.transform.stream.StreamResult;
import javax.xml.transform.stream.StreamSource;
import java.io.StringReader;
import java.io.StringWriter;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class XMLUtilsTest {
    @Test
    void getSecureDocumentBuilderReturnsConfiguredBuilder() throws Exception {
        var builder = XMLUtils.getSecureDocumentBuilder();
        assertNotNull(builder);
    }

    @Test
    void secureDocumentBuilderRejectsDoctypeAndExternalEntities() throws Exception {
        var builder = XMLUtils.getSecureDocumentBuilder();
        var xml = "<!DOCTYPE foo [<!ENTITY xxe SYSTEM \"file:///tmp/autogram-xxe.txt\">]><foo>&xxe;</foo>";

        var exception = assertThrows(Exception.class, () -> builder.parse(new InputSource(new StringReader(xml))));
        assertTrue(containsSecurityHint(messageOf(exception)));
    }

    @Test
    void secureTransformerFactoryBlocksExternalStylesheetAccess() throws Exception {
        var factory = XMLUtils.getSecureTransformerFactory();
        var xslt = """
                <?xml version="1.0"?>
                <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
                    <xsl:import href="file:///tmp/autogram-import.xsl"/>
                    <xsl:template match="/"><out/></xsl:template>
                </xsl:stylesheet>
                """;

        var exception = assertThrows(Exception.class,
                () -> factory.newTransformer(new StreamSource(new StringReader(xslt))));
        assertTrue(messageOf(exception).contains("Access to") || containsSecurityHint(messageOf(exception)));
    }

    @Test
    void secureTransformerFactoryAllowsLocalTransformWithoutExternalResources() throws Exception {
        var factory = XMLUtils.getSecureTransformerFactory();
        var xslt = """
                <?xml version="1.0"?>
                <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
                    <xsl:template match="/"><result><xsl:value-of select="/foo"/></result></xsl:template>
                </xsl:stylesheet>
                """;

        var transformer = factory.newTransformer(new StreamSource(new StringReader(xslt)));
        var writer = new StringWriter();
        transformer.transform(new StreamSource(new StringReader("<foo>hello</foo>")), new StreamResult(writer));

        assertTrue(writer.toString().contains("hello"));
    }

    @Test
    void secureSchemaFactoryBlocksExternalSchemaAndDoctypeAccess() throws Exception {
        var factory = XMLUtils.getSecureSchemaFactory();
        var xsd = """
                <?xml version="1.0"?>
                <!DOCTYPE schema SYSTEM "file:///tmp/autogram-schema.dtd">
                <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
                    <xs:import namespace="urn:test" schemaLocation="file:///tmp/autogram-import.xsd"/>
                    <xs:element name="foo" type="xs:string"/>
                </xs:schema>
                """;

        var exception = assertThrows(Exception.class,
                () -> factory.newSchema(new StreamSource(new StringReader(xsd))));
        assertTrue(messageOf(exception).contains("Access to") || containsSecurityHint(messageOf(exception)));
    }

    @Test
    void secureSchemaFactoryAllowsSimpleSchema() throws Exception {
        var factory = XMLUtils.getSecureSchemaFactory();
        var xsd = """
                <?xml version="1.0"?>
                <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
                    <xs:element name="foo" type="xs:string"/>
                </xs:schema>
                """;

        var schema = factory.newSchema(new StreamSource(new StringReader(xsd)));
        assertNotNull(schema);
    }

    private static boolean containsSecurityHint(String message) {
        if (message == null) {
            return false;
        }

        return message.contains("DOCTYPE is disallowed")
                || message.contains("Access to external")
                || message.contains("disallow-doctype-decl")
                || message.contains("accessExternalDTD")
                || message.contains("access is not allowed");
    }

    private static String messageOf(Throwable throwable) {
        var current = throwable;
        while (current != null) {
            if (current.getMessage() != null && !current.getMessage().isBlank()) {
                return current.getMessage();
            }
            current = current.getCause();
        }
        return "";
    }
}
