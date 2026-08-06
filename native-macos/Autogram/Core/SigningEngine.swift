protocol SigningEngine: Sendable {
    func capabilities() async throws -> EngineCapabilities
    func drivers() async throws -> [SigningDriver]
    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate]
    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection]
    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error>
    func cancel() async
}
