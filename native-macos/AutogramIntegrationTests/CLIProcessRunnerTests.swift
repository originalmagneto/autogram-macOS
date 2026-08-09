import Testing
@testable import Autogram

@Test func helperEventSplitAcrossByteChunksStreamsAsOneMachineEvent() async throws {
    let helper = try FakeMachineHelper(behavior: .splitEvent)
    defer { try? helper.remove() }
    let runner = CLIProcessRunner()
    let request = MachineRequest.capabilities(requestID: "session-1")

    let stream = await runner.run(request: request, configuration: helper.configuration())
    var events: [MachineEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.map(\.type) == [.sessionStarted])
}

@Test func pinExistsOnlyInStandardInputJSON() async throws {
    let helper = try FakeMachineHelper(behavior: .captureInput)
    defer { try? helper.remove() }
    let runner = CLIProcessRunner()
    let pin = "test-pin-value"
    let timestampPassword = "timestamp-password-value"
    let request = SecureMachineRequest(
        envelope: MachineRequest(
            protocolVersion: 1,
            requestID: "certificates-1",
            operation: .certificates,
            payload: ["driver": .string("driver-1")]
        ),
        pin: Secret(pin),
        timestampAuthentication: .basic(username: "timestamp-user", password: Secret(timestampPassword))
    )

    let stream = await runner.run(request: request, configuration: helper.configuration())
    for try await _ in stream {}

    #expect(!(try helper.contents(of: "arguments")).contains(pin))
    #expect(!(try helper.contents(of: "environment")).contains(pin))
    #expect((try helper.contents(of: "standard-input")).contains(pin))
    #expect(!(try helper.contents(of: "arguments")).contains(timestampPassword))
    #expect(!(try helper.contents(of: "environment")).contains(timestampPassword))
    #expect((try helper.contents(of: "standard-input")).contains(timestampPassword))
}

@Test func timeoutTerminatesTheHelperAndFinishesTheStream() async throws {
    let helper = try FakeMachineHelper(behavior: .waits)
    defer { try? helper.remove() }
    let runner = CLIProcessRunner()
    let clock = ContinuousClock()
    let started = clock.now
    let stream = await runner.run(
        request: .capabilities(requestID: "timeout-1"),
        configuration: helper.configuration(timeout: .milliseconds(100))
    )

    do {
        for try await _ in stream {}
        Issue.record("Expected the timed out helper to finish with an error")
    } catch let failure as CLIProcessFailure {
        #expect(failure == .timedOut)
    }

    #expect(clock.now - started < .seconds(3))
}

@Test func terminalEventFinishesEvenWhenNativeCleanupWouldHang() async throws {
    let helper = try FakeMachineHelper(behavior: .terminalThenWaits)
    defer { try? helper.remove() }
    let runner = CLIProcessRunner()
    let stream = await runner.run(
        request: .capabilities(requestID: "terminal-1"),
        configuration: helper.configuration(timeout: .seconds(5))
    )

    var events: [MachineEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.map(\.type) == [.sessionCompleted])
}

@Test func nonZeroExitReturnsRedactedTypedFailure() async throws {
    let helper = try FakeMachineHelper(behavior: .exitsWithError)
    defer { try? helper.remove() }
    let runner = CLIProcessRunner()
    let stream = await runner.run(
        request: .capabilities(requestID: "failure-1"),
        configuration: helper.configuration()
    )

    do {
        for try await _ in stream {}
        Issue.record("Expected the helper failure to finish with an error")
    } catch let failure as CLIProcessFailure {
        #expect(failure == .helperExited)
        #expect(!failure.localizedDescription.contains("test-helper-sensitive-stderr"))
    }
}
