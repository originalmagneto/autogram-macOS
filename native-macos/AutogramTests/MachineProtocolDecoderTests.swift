import Foundation
import Testing
@testable import Autogram

@Test func decodesFragmentedJSONLinesIntoSessionStarted() throws {
    var buffer = JSONLineBuffer(maxLineBytes: 1_048_576)
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "protocol/v1/fixtures/session-events.jsonl")
    let event = try Data(contentsOf: fixtureURL).split(separator: 10, maxSplits: 1)[0]

    #expect(try buffer.append(event.prefix(20)).isEmpty)
    let events = try buffer.append(event.dropFirst(20) + [10])

    #expect(events.map(\.type) == [.sessionStarted])
}

@Test func oversizedLineThrowsLineTooLarge() {
    var buffer = JSONLineBuffer(maxLineBytes: 8)

    #expect(throws: ProtocolFailure.lineTooLarge) {
        try buffer.append(Data(repeating: 65, count: 9))
    }
}

@Test func capabilitiesRequestEncoderMatchesJavaFixtureSemantically() throws {
    let encoded = MachineRequestEncoder.encode(.capabilities(requestID: "request-1"))
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "protocol/v1/fixtures/capabilities-request.json")
    let fixture = try Data(contentsOf: fixtureURL)

    let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
    let fixtureObject = try JSONSerialization.jsonObject(with: fixture) as? NSDictionary
    #expect(encodedObject == fixtureObject)
}

@Test func automaticTimestampSourceOrdersBelgiumBeforeSectigo() {
    #expect(TimestampSource.automatic.endpoints == [
        "http://tsa.belgium.be/connect",
        "http://timestamp.sectigo.com/qualified"
    ])
}

@Test func secureRequestEncodesTimestampCredentialsOnlyInStandardInputPayload() throws {
    let request = SecureMachineRequest(
        envelope: .capabilities(requestID: "request-1"),
        timestampAuthentication: .basic(username: "timestamp-user", password: Secret("timestamp-password"))
    )

    let encoded = MachineRequestEncoder.encode(request)
    let payload = try #require((JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["payload"] as? [String: Any])
    let timestamp = try #require(payload["timestamp"] as? [String: Any])
    let authentication = try #require(timestamp["authentication"] as? [String: Any])
    #expect(authentication["type"] as? String == "basic")
    #expect(authentication["username"] as? String == "timestamp-user")
    #expect(authentication["password"] as? String == "timestamp-password")
}
