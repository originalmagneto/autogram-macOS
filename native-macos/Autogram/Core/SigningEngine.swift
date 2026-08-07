protocol SigningEngine: Sendable {
    func capabilities() async throws -> EngineCapabilities
    func drivers() async throws -> [SigningDriver]
    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate]
    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery
    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection]
    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error>
    func cancel() async
}

extension SigningEngine {
    func certificateDiscovery(driverID: String, pin: Secret?) async throws -> CertificateDiscovery {
        CertificateDiscovery(
            token: SigningToken(tokenKey: "", providerName: ""),
            certificates: try await certificates(driverID: driverID, pin: pin)
        )
    }
}
