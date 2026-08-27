import Foundation

enum MachineRequestEncoder {
    static func encode(_ request: MachineRequest) -> Data {
        encode(SecureMachineRequest(envelope: request))
    }

    static func encode(_ request: SecureMachineRequest) -> Data {
        var pinBytes = request.pin?.consumeBytes() ?? []
        defer { pinBytes.zeroize() }
        var authenticationBytes: [UInt8] = []
        defer { authenticationBytes.zeroize() }

        var payload = request.envelope.payload
        // Neautentizované operácie (napr. DRIVERS) musia mať skutočne prázdny payload.
        if request.pin != nil {
            payload["pin"] = .string(String(decoding: pinBytes, as: UTF8.self))
        }
        if let authentication = request.timestampAuthentication {
            let encodedAuthentication: [String: JSONValue]
            switch authentication {
            case .basic(let username, let password):
                authenticationBytes = password.consumeBytes() ?? []
                encodedAuthentication = [
                    "type": .string("basic"),
                    "username": .string(username),
                    "password": .string(String(decoding: authenticationBytes, as: UTF8.self))
                ]
            case .bearer(let token):
                authenticationBytes = token.consumeBytes() ?? []
                encodedAuthentication = [
                    "type": .string("bearer"),
                    "token": .string(String(decoding: authenticationBytes, as: UTF8.self))
                ]
            }
            var timestamp = object(in: payload["timestamp"]) ?? [:]
            timestamp["authentication"] = .object(encodedAuthentication)
            payload["timestamp"] = .object(timestamp)
        }
        let envelope = MachineRequest(
            protocolVersion: request.envelope.protocolVersion,
            requestID: request.envelope.requestID,
            operation: request.envelope.operation,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(envelope)) ?? Data()
    }

    private static func object(in value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }
}

enum MachineProtocolDecoder {
    static func decode(_ data: Data) throws -> MachineEvent {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProtocolFailure.malformedJSON
        }
        let allowedKeys: Set<String> = ["protocolVersion", "type", "sessionId", "emittedAt", "fileId", "payload"]
        let requiredKeys: Set<String> = ["protocolVersion", "type", "sessionId", "emittedAt", "payload"]
        guard Set(object.keys).isSubset(of: allowedKeys),
              requiredKeys.isSubset(of: Set(object.keys)),
              object["payload"] as? [String: Any] != nil else {
            throw ProtocolFailure.malformedPayload
        }
        guard let version = object["protocolVersion"] as? Int, version == 1 else {
            throw ProtocolFailure.unsupportedProtocolVersion
        }
        guard let typeValue = object["type"] as? String, let type = MachineEventType(rawValue: typeValue) else {
            throw ProtocolFailure.unknownEventType
        }
        guard let sessionID = object["sessionId"] as? String, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProtocolFailure.missingSessionID
        }
        guard let emittedAt = object["emittedAt"] as? String, isValidTimestamp(emittedAt) else {
            throw ProtocolFailure.malformedPayload
        }
        let fileID = object["fileId"] as? String
        let fileIDIsNullOrString = object["fileId"] == nil || object["fileId"] is NSNull || fileID != nil
        guard fileIDIsNullOrString,
              type.requiresFileID == (fileID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) else {
            throw ProtocolFailure.invalidFileID
        }
        guard let event = try? JSONDecoder().decode(MachineEvent.self, from: data) else {
            throw ProtocolFailure.malformedPayload
        }
        return event
    }

    private static func isValidTimestamp(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: value) != nil {
            return true
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value) != nil
    }
}
