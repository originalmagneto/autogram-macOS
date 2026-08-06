import Foundation

enum MachineRequestEncoder {
    static func encode(_ request: MachineRequest, pin: [UInt8]? = nil) -> Data {
        var payload = request.payload
        if let pin {
            payload["pin"] = .string(String(decoding: pin, as: UTF8.self))
        }
        let envelope = MachineRequest(
            protocolVersion: request.protocolVersion,
            requestID: request.requestID,
            operation: request.operation,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(envelope)) ?? Data()
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
        guard let emittedAt = object["emittedAt"] as? String, ISO8601DateFormatter().date(from: emittedAt) != nil else {
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
}
