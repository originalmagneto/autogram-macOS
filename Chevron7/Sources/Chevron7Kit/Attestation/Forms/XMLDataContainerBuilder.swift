// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Wraps a form document into an XMLDataContainer 1.1 exactly as the record EZZK accepted
/// on 2026-08-24: schema and presentation referenced by URI with C14N SHA-256 digests.
public enum XMLDataContainerBuilder {
    public static let namespace = "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1"
    private static let sha256 = "urn:oid:2.16.840.1.101.3.4.2.1"
    private static let c14n = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"

    /// `formXML` is the form's root element without an XML declaration.
    public static func build(formXML: String, form: OfficialForm) -> Data {
        precondition(!formXML.hasPrefix("<?xml"), "pass the form element without an XML declaration")
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        x += "<XMLDataContainer xmlns=\"\(namespace)\">"
        x += "<XMLData ContentType=\"application/xml; charset=UTF-8\" Identifier=\"\(form.identifier)\" Version=\"\(form.version)\">"
        x += formXML
        x += "</XMLData><UsedSchemasReferenced>"
        x += "<UsedXSDReference DigestMethod=\"\(sha256)\" DigestValue=\"\(form.schemaDigestBase64)\" TransformAlgorithm=\"\(c14n)\">\(form.schemaURI)</UsedXSDReference>"
        x += "<UsedPresentationSchemaReference ContentType=\"application/xslt+xml\" DigestMethod=\"\(sha256)\" DigestValue=\"\(form.presentationDigestBase64)\" MediaDestinationTypeDescription=\"\(form.presentationMediaDestination)\" TransformAlgorithm=\"\(c14n)\">\(form.presentationURI)</UsedPresentationSchemaReference>"
        x += "</UsedSchemasReferenced></XMLDataContainer>"
        return Data(x.utf8)
    }
}
