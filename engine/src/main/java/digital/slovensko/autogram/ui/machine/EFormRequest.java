package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.eforms.dto.EFormAttributes;
import digital.slovensko.autogram.core.eforms.dto.XsltParams;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * eForm and XML Data Container attributes carried by a machine protocol sign
 * request. The field set mirrors {@code ServerSigningParameters} so the machine
 * entry point and the HTTP server entry point cannot drift apart; both end up in
 * {@code SigningParameters.buildParameters}.
 *
 * {@code schema} and {@code transformation} are base64, as on the server.
 */
public record EFormRequest(
        String containerXmlns,
        String schema,
        String transformation,
        String identifier,
        String schemaIdentifier,
        String transformationIdentifier,
        String transformationLanguage,
        String transformationMediaDestinationTypeDescription,
        String transformationTargetEnvironment,
        boolean embedUsedSchemas,
        boolean autoLoadEform,
        String fsFormId,
        String packaging) {

    public EFormAttributes toAttributes() {
        var xsltParams = new XsltParams(
                transformationIdentifier,
                transformationLanguage,
                transformationMediaDestinationTypeDescription,
                transformationTargetEnvironment,
                null);

        return new EFormAttributes(
                identifier,
                decode(transformation),
                decode(schema),
                containerXmlns,
                schemaIdentifier,
                xsltParams,
                embedUsedSchemas);
    }

    private static String decode(String base64) {
        if (base64 == null || base64.isEmpty()) {
            return null;
        }
        try {
            return new String(Base64.getDecoder().decode(base64), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException exception) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST", exception);
        }
    }
}
