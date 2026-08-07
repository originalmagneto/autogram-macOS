import Foundation

final class AutogramCLIEngine: SigningEngine, @unchecked Sendable {
    private let runner: CLIProcessRunner
    private let configuration: ProcessConfiguration
    private let driverResolver: DriverResolver
    private let outputService: OutputService
    private let lock = NSLock()
    private var reservations: [String: OutputReservation] = [:]

    init(
        configuration: ProcessConfiguration = .production,
        runner: CLIProcessRunner = .init(),
        driverResolver: DriverResolver = .init(),
        outputService: OutputService = .init()
    ) {
        self.configuration = configuration
        self.runner = runner
        self.driverResolver = driverResolver
        self.outputService = outputService
    }

    func capabilities() async throws -> EngineCapabilities {
        let events = try await run(.capabilities(requestID: UUID().uuidString))
        let payload = try completedPayload(from: events)
        guard let protocolVersion = events.first?.protocolVersion else {
            throw SigningFailure.engine("The signing helper returned no capability response.")
        }
        let signatureLevels = strings(in: payload["signatureLevels"])
        let timestampPolicy = object(in: payload["timestampPolicy"])
        guard signatureLevels.contains("PAdES_BASELINE_T"),
              timestampPolicy?["required"] == .bool(true),
              timestampPolicy?["qualified"] == .bool(true) else {
            throw SigningFailure.engine("The signing helper does not require qualified timestamps.")
        }
        return EngineCapabilities(protocolVersion: protocolVersion, supportsQualifiedTimestamp: true)
    }

    func drivers() async throws -> [SigningDriver] {
        let events = try await run(MachineRequest(protocolVersion: 1, requestID: UUID().uuidString, operation: .drivers, payload: [:]))
        let payload = try payload(for: .driverDetected, in: events)
        let candidates = array(in: payload["drivers"]) ?? []
        return try candidates.compactMap { candidate in
            guard let id = string(in: candidate["id"]), let name = string(in: candidate["name"]),
                  let path = string(in: candidate["path"]) else { return nil }
            let resolved = try driverResolver.resolve(
                helperURL: configuration.executableURL,
                driver: DriverCandidate(url: URL(fileURLWithPath: path))
            )
            return SigningDriver(
                id: id,
                displayName: name,
                middlewareVersion: resolved.middlewareVersion,
                tokenPresent: bool(in: candidate["tokenPresent"])
            )
        }
    }

    func certificates(driverID: String, pin: Secret?) async throws -> [SigningCertificate] {
        let request = MachineRequest(
            protocolVersion: 1,
            requestID: UUID().uuidString,
            operation: .certificates,
            payload: ["driver": .string(driverID)]
        )
        let events = try await run(SecureMachineRequest(envelope: request, pin: pin))
        let payload = try payload(for: .certificatesAvailable, in: events)
        return (array(in: payload["certificates"]) ?? []).compactMap { certificate in
            guard let serial = string(in: certificate["serial"]), let name = string(in: certificate["commonName"]) else {
                return nil
            }
            return SigningCertificate(serialNumber: serial, displayName: name)
        }
    }

    func inspect(files: [PDFItemDescriptor]) async throws -> [PDFInspection] {
        let machineFiles = try files.map { file in
            let reservation = try reservation(for: file.id, sourceURL: file.sourceURL)
            return machineFile(id: file.id, sourceURL: file.sourceURL, targetURL: reservation.temporaryURL)
        }
        let request = MachineRequest(
            protocolVersion: 1,
            requestID: UUID().uuidString,
            operation: .inspect,
            payload: ["files": .array(machineFiles)]
        )
        let events = try await run(request)
        return [PDFInspection(files: files.map { file in
            let inspected = events.contains { $0.type == .inspectionCompleted && $0.fileID == file.id }
            return InspectedPDF(id: file.id, isSignable: inspected)
        })]
    }

    func sign(request: SigningRequest) -> AsyncThrowingStream<SigningEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let files = try request.files.map { file in
                        let reservation = try reservation(for: file.id, sourceURL: file.sourceURL)
                        try FileManager.default.removeItem(at: reservation.temporaryURL)
                        return machineFile(id: file.id, sourceURL: file.sourceURL, targetURL: reservation.finalURL)
                    }
                    let machineRequest = MachineRequest(
                        protocolVersion: 1,
                        requestID: request.sessionID.uuidString,
                        operation: .sign,
                        payload: [
                            "driver": .string(request.driverID),
                            "certificateSerial": .string(request.certificateSerial),
                            "signatureLevel": .string("PAdES_BASELINE_T"),
                            "timestamp": .object([
                                "required": .bool(true),
                                "servers": .array([
                                    .string("http://timestamp.sectigo.com/qualified"),
                                    .string("http://tsa.belgium.be/connect")
                                ])
                            ]),
                            "files": .array(files)
                        ]
                    )
                    let events = try await run(SecureMachineRequest(envelope: machineRequest, pin: request.pin))
                    var completed = Set<String>()
                    continuation.yield(.started)
                    for event in events {
                        switch event.type {
                        case .fileSigningStarted:
                            if let fileID = event.fileID { continuation.yield(.fileSigning(fileID)) }
                        case .fileCompleted:
                            guard let fileID = event.fileID else { continue }
                            do {
                                try finalizeOutput(for: fileID)
                                completed.insert(fileID)
                                continuation.yield(.completed(fileID))
                            } catch {
                                continuation.yield(.failed(fileID, .fileFailed(fileID)))
                            }
                        case .fileFailed:
                            if let fileID = event.fileID { continuation.yield(.failed(fileID, .fileFailed(fileID))) }
                        default:
                            break
                        }
                    }
                    _ = try completedPayload(from: events)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancel() async {
        await runner.cancel()
    }

    private func reservation(for fileID: String, sourceURL: URL) throws -> OutputReservation {
        lock.lock()
        defer { lock.unlock() }
        if let reservation = reservations[fileID] { return reservation }
        let reservation = try outputService.reserve(for: sourceURL)
        reservations[fileID] = reservation
        return reservation
    }

    private func finalizeOutput(for fileID: String) throws {
        lock.lock()
        let reservation = reservations.removeValue(forKey: fileID)
        lock.unlock()
        guard let reservation else { throw OutputServiceError.unableToFinalize }
        try FileManager.default.moveItem(at: reservation.finalURL, to: reservation.temporaryURL)
        try outputService.finalize(reservation)
    }

    private func run(_ request: MachineRequest) async throws -> [MachineEvent] {
        try await run(SecureMachineRequest(envelope: request))
    }

    private func run(_ request: SecureMachineRequest) async throws -> [MachineEvent] {
        let stream = await runner.run(request: request, configuration: configuration)
        var events: [MachineEvent] = []
        for try await event in stream {
            guard event.sessionID == request.envelope.requestID else {
                throw SigningFailure.engine("The signing helper returned an invalid session.")
            }
            events.append(event)
        }
        if let failure = events.last(where: { $0.type == .sessionFailed }) {
            let code = string(in: failure.payload["code"]) ?? "INTERNAL_ERROR"
            let fallback = string(in: failure.payload["fallbackMessage"])
                ?? "The signing helper rejected the request."
            throw SigningFailure.engine("\(fallback) [\(code)]")
        }
        return events
    }

    private func completedPayload(from events: [MachineEvent]) throws -> [String: JSONValue] {
        guard let event = events.last(where: { $0.type == .sessionCompleted }) else {
            throw SigningFailure.engine("The signing helper did not confirm completion.")
        }
        return event.payload
    }

    private func payload(for type: MachineEventType, in events: [MachineEvent]) throws -> [String: JSONValue] {
        guard let payload = events.last(where: { $0.type == type })?.payload else {
            throw SigningFailure.engine("The signing helper returned an incomplete response.")
        }
        return payload
    }

    private func machineFile(id: String, sourceURL: URL, targetURL: URL) -> JSONValue {
        .object([
            "id": .string(id),
            "source": .string(sourceURL.standardizedFileURL.path),
            "target": .string(targetURL.standardizedFileURL.path)
        ])
    }

    private func object(in value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private func array(in value: JSONValue?) -> [[String: JSONValue]]? {
        guard case .array(let values)? = value else { return nil }
        return values.compactMap { object(in: $0) }
    }

    private func strings(in value: JSONValue?) -> [String] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap { string(in: $0) }
    }

    private func string(in value: JSONValue?) -> String? {
        guard case .string(let value)? = value else { return nil }
        return value
    }

    private func bool(in value: JSONValue?) -> Bool? {
        guard case .bool(let value)? = value else { return nil }
        return value
    }
}

private extension ProcessConfiguration {
    static var production: ProcessConfiguration {
        ProcessConfiguration(
            executableURL: Bundle.main.bundleURL.appending(path: "Contents/Helpers/AutogramCLI-arm64"),
            timeout: .seconds(90),
            environment: ProcessConfiguration.signingHelperEnvironment()
        )
    }
}
