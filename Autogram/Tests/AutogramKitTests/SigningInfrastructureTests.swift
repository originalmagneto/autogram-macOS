import XCTest
import Security
@testable import AutogramKit

final class SigningInfrastructureTests: XCTestCase {
    static let fixtureCertBase64 = """
    MIIDijCCAnKgAwIBAgIJAKtUqYzrHwrSMA0GCSqGSIb3DQEBCwUAMFoxCzAJBgNVBAYTAlNLMSMwIQYDVQQKDBpUZXN0IEFkdm9rYXRza2EgS2FuY2VsYXJpYTEmMCQGA1UEAwwdTWFuZGF0bnkgVGVzdG92YWNpIENlcnRpZmlrYXQwHhcNMjYwODIzMTg0MzE5WhcNMjcwODIzMTg0MzE5WjBaMQswCQYDVQQGEwJTSzEjMCEGA1UECgwaVGVzdCBBZHZva2F0c2thIEthbmNlbGFyaWExJjAkBgNVBAMMHU1hbmRhdG55IFRlc3RvdmFjaSBDZXJ0aWZpa2F0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1ojiVYIFgcRoMwKryBlAHP7MvKKA0KCirocsZFfJOlcKWnvyDxRJ55TzQqbf1m+81aChLIG/lRfyVNP+KJBKT3zP6REfbObECwF0uBbRQ8zWDo/qWBqu75Jmo26tei5PQd/umkPV4F0aKl5oqAotuxQNV9rocwV0MiuvWfkO+zTT5NwNRSAwxryHVmqe57yvblrpADb3YVD+xf9S37geK3EqGvdtpgT8/fC9aTCKIF7ZJe27GGAwff1ED0P/Th3Hmvt83btaYAPw7mwqndZydKAqZt6BQEkvM3X4AfyATb8iROlvO5titXT0egf3UdHwp8//lOe0FsETi56GLkH74QIDAQABo1MwUTAdBgNVHQ4EFgQUTMTRofKL4/K+GN/+4+neoA23KcQwHwYDVR0jBBgwFoAUTMTRofKL4/K+GN/+4+neoA23KcQwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAztMJW+bt4Et8AJ71PpH6c8bmf2GPlWW9urbN7E4tJ3bYpSwd4ho/BI20serdPzlQnFLoGQB8V76qz+9tEMdnSPC4w1eU54i/GwJjCYqZ+ABgLZxOzZV9oqfp7NB0JhZPCHKVUTDPI1z5r1BWv+1muh7Tl2DAyPUh5i+3GIwLa9FYsu+wf+m6l/IryRSvtaDo1v0LHBRn93IL5tpJF+EPz3BbLcwnJlCw4IVmwGylqsPhnHBRIvZHVfhr2X68tJvo/khueAv2p8JDp/w5Z//V0deKmncNOK1Nvsgmpp9PGyRWiR48sIfEr7DnXfVNVUWO5+2wQQXbhfeakaQs8ziM8w==
    """

    func testCertificateFactsParsing() throws {
        let der = Data(base64Encoded: Self.fixtureCertBase64.replacingOccurrences(of: "\n", with: ""))!
        let facts = try XCTUnwrap(X509Inspector.facts(certificateData: der))

        XCTAssertEqual(facts.serialNumberDecimal, "12345678901234567890")
        XCTAssertEqual(facts.subjectRFC2253,
                       "CN=Mandatny Testovaci Certifikat,O=Test Advokatska Kancelaria,C=SK")
        XCTAssertEqual(facts.issuerRFC2253, facts.subjectRFC2253,
                       "Self-signed certifikát má issuer == subject")
    }

    func testBigSerialDecimalConversion() {
        XCTAssertEqual(X509Inspector.decimalString(fromBytes: [0x00]), "0")
        XCTAssertEqual(X509Inspector.decimalString(fromBytes: [0x01, 0x00]), "256")
        XCTAssertEqual(X509Inspector.decimalString(fromBytes: [0xFF]), "255")
        XCTAssertEqual(
            X509Inspector.decimalString(fromBytes: [0xAB, 0x54, 0xA9, 0x8C, 0xEB, 0x1F, 0x0A, 0xD2]),
            "12345678901234567890")
    }

    func testRFC2253Escaping() {
        XCTAssertEqual(X509Inspector.escape2253("První certifikační autorita, s.r.o."),
                       "První certifikační autorita\\, s.r.o.")
        XCTAssertEqual(X509Inspector.escape2253("A+B \"Q\""), "A\\+B \\\"Q\\\"")
        XCTAssertEqual(X509Inspector.escape2253("#leading"), "\\#leading")
    }

    func testExclusiveC14NAddsSortedNamespacesAndExpandsEmptyTags() {
        let source = "<xades:SignedProperties Id=\"xades-id-1\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/></xades:SignedProperties>"
        let canonical = XAdESSigner.exclusiveC14N(
            source,
            namespaces: [("xades", XAdESSigner.xadesNS), ("ds", XAdESSigner.dsNS)])
        XCTAssertTrue(canonical.hasPrefix("<xades:SignedProperties xmlns:xades=\"\(XAdESSigner.xadesNS)\" Id=\"xades-id-1\">"))
        XCTAssertTrue(canonical.contains("<ds:DigestMethod xmlns:ds=\"\(XAdESSigner.dsNS)\" Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"></ds:DigestMethod>"))
        XCTAssertFalse(canonical.contains("/>"))
    }

    func testProviderSelectionPrefersEngineWhenInstalled() {
        let provider = SigningProviderFactory.makeDefault()
        if JavaEngineLocator().locate()?.helperURL.path.contains("Helpers") == true,
           FileManager.default.isExecutableFile(atPath: "/Applications/Autogram macOS 2.app/Contents/Helpers/AutogramCLI-arm64") {
            XCTAssertTrue(provider is EngineBridgeSigningProvider,
                          "Pri nainštalovanom engine musí factory preferovať EngineBridgeSigningProvider.")
            return
        }
        let hasRealIdentity = KeychainIdentityScanner.scanAll().contains { $0.hasPrivateKey }
        if hasRealIdentity {
            XCTAssertTrue(provider is KeychainXAdESSigningProvider)
        } else {
            XCTAssertTrue(provider is DemoSigningProvider)
        }
    }
}
