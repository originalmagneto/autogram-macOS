import Foundation

protocol SigningEngine: Sendable {
    func capabilities() async throws -> EngineCapabilities
    func drivers() async throws -> [SigningDriver]
    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate]
    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery
    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection]
    func previewEmbeddedDocument(sourceURL: URL, named: String) async throws -> EmbeddedDocumentPreview
    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection]
    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error>
    func cancel() async
}

extension SigningEngine {
    func previewEmbeddedDocument(sourceURL: URL, named: String) async throws -> EmbeddedDocumentPreview {
        throw SigningFailure.engine("This signing engine does not support embedded document previews.")
    }

    func validate(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        throw SigningFailure.engine("This signing engine does not support complete validation.")
    }
}
