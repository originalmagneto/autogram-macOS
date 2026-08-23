import Foundation
import Security

public final class KeychainXAdESSigningProvider: QualifiedSigningProviding, @unchecked Sendable {
    public init() {}

    public func availableIdentities() async -> [SigningIdentityInfo] {
        KeychainIdentityScanner.scanAll().filter { $0.hasPrivateKey }
    }

    public func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        guard let resolved = KeychainIdentityScanner.resolveIdentity(id: request.identityID) else {
            throw SigningError.identityUnavailable
        }

        var certificateRef: SecCertificate?
        guard SecIdentityCopyCertificate(resolved.identity, &certificateRef) == errSecSuccess,
              let certificate = certificateRef else {
            throw XAdESError.certificateUnavailable
        }
        let certificateDER = Data(SecCertificateCopyData(certificate) as Data)

        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(resolved.identity, &privateKey) == errSecSuccess,
              let key = privateKey else {
            throw XAdESError.keyUnavailable
        }

        var tsaURL: URL?
        if request.includeTimestamp,
           let urlString = request.tsaURL, !urlString.isEmpty {
            tsaURL = URL(string: urlString)
            if tsaURL?.scheme == nil { throw SigningError.timestampFailed }
        }

        switch request.outputFormat {
        case .embeddedPAdES:
            let signedPDF = try await PAdESSigner().sign(
                pdf: request.pdfData,
                certificateDER: certificateDER,
                privateKey: key,
                includeTimestamp: request.includeTimestamp,
                tsaURL: tsaURL)
            return SignedConversionResult(
                pdfData: signedPDF,
                asicData: nil,
                signedAt: Date(),
                signatureLabel: "PAdES-B/T — \(resolved.summary)",
                isLegallyBinding: true)
        case .attachedASIC:
            return try await signASIC(request: request,
                                      identity: resolved.identity,
                                      summary: resolved.summary,
                                      certificateDER: certificateDER,
                                      tsaURL: tsaURL)
        }
    }

    private func signASIC(request: SigningRequest, identity: SecIdentity, summary: String,
                          certificateDER: Data, tsaURL: URL?) async throws -> SignedConversionResult {
        let payload = request.extraFiles
            .filter { $0.path != "mimetype" && !$0.path.hasPrefix("META-INF/") }
            .sorted { $0.path < $1.path }

        let dataObjects = payload.map { entry in
            XAdESSigner.DataObject(uri: entry.path,
                                   mimeType: ASiCEPackager.mediaType(forPath: entry.path),
                                   data: entry.data)
        }
        guard !dataObjects.isEmpty else {
            throw SigningError.signingFailed("Kontajner neobsahuje žiadne dáta na podpis.")
        }

        let result = try await XAdESSigner().sign(dataObjects: dataObjects,
                                                  identity: identity,
                                                  includeTimestamp: request.includeTimestamp,
                                                  tsaURL: tsaURL)

        var files: [ASiCEPackager.Entry] = [
            ASiCEPackager.Entry(path: "mimetype",
                                data: Data(ASiCEPackager.asicMimeType.utf8),
                                storeUncompressed: true)
        ]
        files.append(contentsOf: payload)
        let manifestEntries = payload.map { (path: $0.path, mediaType: ASiCEPackager.mediaType(forPath: $0.path)) }
        files.append(ASiCEPackager.Entry(path: "META-INF/manifest.xml",
                                         data: Data(ASiCEPackager.manifestXML(entries: manifestEntries).utf8)))
        files.append(ASiCEPackager.Entry(path: "META-INF/signatures001.xml",
                                         data: Data(result.signatureXML.utf8)))

        let asic = try ASiCEPackager().package(files: files)

        return SignedConversionResult(
            pdfData: request.pdfData,
            asicData: asic,
            signedAt: Date(),
            signatureLabel: "KEP XAdES-B/T — \(summary)",
            isLegallyBinding: true,
            timestampGenTime: result.timestampGenTime,
            timestampToken: nil)
    }
}
