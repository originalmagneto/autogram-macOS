import Foundation

enum ProtocolFailure: Error, Sendable, Equatable, LocalizedError {
    case unsupportedProtocolVersion
    case unknownEventType
    case missingSessionID
    case invalidFileID
    case malformedJSON
    case malformedPayload
    case lineTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocolVersion: "Unsupported machine protocol version."
        case .unknownEventType: "Unknown machine event type."
        case .missingSessionID: "Machine event is missing a session identifier."
        case .invalidFileID: "Machine event has an invalid file identifier."
        case .malformedJSON: "Machine output is not valid protocol JSON."
        case .malformedPayload: "Machine event payload is malformed."
        case .lineTooLarge: "Machine protocol line exceeds the configured limit."
        }
    }
}

enum MachineOperation: String, Codable, Sendable, Equatable {
    case capabilities = "CAPABILITIES"
    case drivers = "DRIVERS"
    case certificates = "CERTIFICATES"
    case inspect = "INSPECT"
    case sign = "SIGN"
}

struct MachineRequest: Codable, Sendable, Equatable {
    let protocolVersion: Int
    let requestID: String
    let operation: MachineOperation
    let payload: [String: JSONValue]

    static func capabilities(requestID: String) -> MachineRequest {
        MachineRequest(protocolVersion: 1, requestID: requestID, operation: .capabilities, payload: [:])
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestID = "requestId"
        case operation
        case payload
    }
}

struct SecureMachineRequest: Sendable {
    let envelope: MachineRequest
    let pin: Secret?

    init(envelope: MachineRequest, pin: Secret? = nil) {
        self.envelope = envelope
        self.pin = pin
    }
}

enum MachineEventType: String, Codable, Sendable, Equatable {
    case sessionStarted = "session.started"
    case driverDetected = "driver.detected"
    case certificatesAvailable = "certificates.available"
    case inspectionCompleted = "inspection.completed"
    case pinRequired = "pin.required"
    case fileSigningStarted = "file.signingStarted"
    case fileProgress = "file.progress"
    case fileCompleted = "file.completed"
    case fileFailed = "file.failed"
    case sessionCompleted = "session.completed"
    case sessionFailed = "session.failed"

    var requiresFileID: Bool {
        switch self {
        case .fileSigningStarted, .fileProgress, .fileCompleted, .fileFailed: true
        default: false
        }
    }
}

struct MachineEvent: Codable, Sendable, Equatable {
    let protocolVersion: Int
    let type: MachineEventType
    let sessionID: String
    let emittedAt: String
    let fileID: String?
    let payload: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case type
        case sessionID = "sessionId"
        case emittedAt
        case fileID = "fileId"
        case payload
    }
}

indirect enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
