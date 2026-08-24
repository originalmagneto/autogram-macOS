import Foundation
import Security
import CryptoKit

public final class KeychainXAdESSigningProvider: QualifiedSigningProviding, @unchecked Sendable {
    public init() {}

    public func availableIdentities() async -> [SigningIdentityInfo] {
        KeychainIdentityScanner.scanAll()
    }

    public func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        let identities = await availableIdentities()
        guard let identity = identities.first(where: { $0.id == request.identityID }) else {
            throw SigningError.identityUnavailable
        }

        var tsaURL: URL?
        if request.includeTimestamp,
           let urlString = request.tsaURL, !urlString.isEmpty {
            tsaURL = URL(string: urlString)
            if tsaURL?.scheme == nil { throw SigningError.timestampFailed }
        }

        let signer: RawSigner
        let certificateDER: Data
        let summary = identity.label

        if let certHex = identity.pkcs11CertSHA256Hex {
            let pin = request.pin ?? ""
            guard !pin.isEmpty else { throw PKCS11Error.loginFailed(0xA0) }
            guard let remote = PKCS11BridgeClient.listIdentities().first(where: { $0.certSHA256Hex == certHex }) else {
                throw SigningError.identityUnavailable
            }
            guard let cert = SecCertificateCreateWithData(nil, remote.certificateDER as CFData) else {
                throw XAdESError.certificateUnavailable
            }
            certificateDER = remote.certificateDER
            signer = .pkcs11(certSHA256Hex: certHex,
                             isRSA: remote.isRSA,
                             pin: pin)
            _ = identity.pkcs11IsRSA
        } else {
            guard let resolved = KeychainIdentityScanner.resolveIdentityPair(id: request.identityID) else {
                throw SigningError.identityUnavailable
            }
            certificateDER = Data(SecCertificateCopyData(resolved.certificate) as Data)
            signer = .secKey(resolved.privateKey)
        }

        switch request.outputFormat {
        case .embeddedPAdES:
            let signedPDF = try await PAdESSigner().sign(
                pdf: request.pdfData,
                certificateDER: certificateDER,
                signer: signer,
                includeTimestamp: request.includeTimestamp,
                tsaURL: tsaURL)
            return SignedConversionResult(
                pdfData: signedPDF,
                asicData: nil,
                signedAt: Date(),
                signatureLabel: "PAdES-B/T — \(summary)",
                isLegallyBinding: true)
        case .attachedASIC:
            return try await signASIC(request: request,
                                      certificate: certificateDER,
                                      signer: signer,
                                      summary: summary,
                                      tsaURL: tsaURL)
        }
    }

    private func signASIC(request: SigningRequest, certificate: Data, signer: RawSigner,
                          summary: String, tsaURL: URL?) async throws -> SignedConversionResult {
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

        guard let certificate = SecCertificateCreateWithData(nil, certificate as CFData) else {
            throw XAdESError.certificateUnavailable
        }

        let result = try await XAdESSigner().sign(dataObjects: dataObjects,
                                                  certificate: certificate,
                                                  signer: signer,
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
