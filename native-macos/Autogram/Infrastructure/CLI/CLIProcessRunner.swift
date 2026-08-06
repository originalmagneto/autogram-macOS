import Foundation

enum CLIProcessFailure: Error, Sendable, Equatable, LocalizedError {
    case launchFailed
    case malformedOutput
    case helperExited
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .launchFailed: "The signing helper could not be started."
        case .malformedOutput: "The signing helper returned invalid machine output."
        case .helperExited: "The signing helper did not complete successfully."
        case .timedOut: "The signing helper did not finish in time."
        case .cancelled: "The signing operation was cancelled."
        }
    }
}

actor CLIProcessRunner {
    private struct ActiveRun {
        let id: UUID
        let process: Process
        let stdout: FileHandle
        let stderr: FileHandle
        let continuation: AsyncThrowingStream<MachineEvent, Error>.Continuation
        var stdoutBuffer: JSONLineBuffer
        let maxStderrBytes: Int
        var capturedStderr = Data()
        var terminationStatus: Int32?
        var stdoutFinished = false
        var stderrFinished = false
        var requestedFailure: CLIProcessFailure?
        var timeoutTask: Task<Void, Never>?
    }

    private var activeRun: ActiveRun?

    func run(
        request: MachineRequest,
        configuration: ProcessConfiguration
    ) -> AsyncThrowingStream<MachineEvent, Error> {
        run(request: SecureMachineRequest(envelope: request), configuration: configuration)
    }

    func run(
        request: SecureMachineRequest,
        configuration: ProcessConfiguration
    ) -> AsyncThrowingStream<MachineEvent, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task {
                self.start(
                    id: id,
                    request: request,
                    configuration: configuration,
                    continuation: continuation
                )
            }
        }
    }

    func cancel() async {
        guard let activeRun else { return }
        stop(runID: activeRun.id, failure: .cancelled)
    }

    private func start(
        id: UUID,
        request: SecureMachineRequest,
        configuration: ProcessConfiguration,
        continuation: AsyncThrowingStream<MachineEvent, Error>.Continuation
    ) {
        guard activeRun == nil else {
            continuation.finish(throwing: CLIProcessFailure.launchFailed)
            return
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = [
            "--cli",
            "--machine-readable",
            "--protocol-version",
            "1",
            "--operation",
            request.envelope.operation.rawValue
        ]
        process.environment = configuration.environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task {
                await self?.processTerminated(runID: id, status: status)
            }
        }

        activeRun = ActiveRun(
            id: id,
            process: process,
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            continuation: continuation,
            stdoutBuffer: JSONLineBuffer(maxLineBytes: configuration.maxStdoutLineBytes),
            maxStderrBytes: configuration.maxStderrBytes
        )
        startReaders(for: id, stdout: stdout.fileHandleForReading, stderr: stderr.fileHandleForReading)

        var pinBytes: [UInt8] = []
        var didConsumePIN = false
        defer {
            if !didConsumePIN {
                pinBytes = request.pin?.consumeBytes() ?? []
            }
            for index in pinBytes.indices {
                pinBytes[index] = 0
            }
        }

        do {
            try process.run()
            pinBytes = request.pin?.consumeBytes() ?? []
            didConsumePIN = true
            let encodedRequest = MachineRequestEncoder.encode(request.envelope, pin: pinBytes.isEmpty ? nil : pinBytes)
            stdin.fileHandleForWriting.write(encodedRequest)
            stdin.fileHandleForWriting.write(Data([10]))
            try stdin.fileHandleForWriting.close()
            scheduleTimeout(for: id, duration: configuration.timeout)
        } catch {
            try? stdin.fileHandleForWriting.close()
            finish(runID: id, throwing: .launchFailed)
        }
    }

    private func startReaders(for runID: UUID, stdout: FileHandle, stderr: FileHandle) {
        let stdoutChunks = Self.chunks(from: stdout)
        Task { [weak self] in
            for await chunk in stdoutChunks {
                await self?.consumeStdout(chunk, runID: runID)
            }
            await self?.stdoutDidFinish(runID: runID)
        }

        let stderrChunks = Self.chunks(from: stderr)
        Task { [weak self] in
            for await chunk in stderrChunks {
                await self?.consumeStderr(chunk, runID: runID)
            }
            await self?.stderrDidFinish(runID: runID)
        }
    }

    private static func chunks(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { readableHandle in
                let data = readableHandle.availableData
                guard !data.isEmpty else {
                    readableHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                continuation.yield(data)
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    private func consumeStdout(_ data: Data, runID: UUID) {
        guard var activeRun, activeRun.id == runID else { return }
        do {
            let events = try activeRun.stdoutBuffer.append(data)
            self.activeRun = activeRun
            for event in events {
                activeRun.continuation.yield(event)
            }
        } catch {
            self.activeRun = activeRun
            stop(runID: runID, failure: .malformedOutput)
        }
    }

    private func consumeStderr(_ data: Data, runID: UUID) {
        guard var activeRun, activeRun.id == runID else { return }
        let remaining = max(0, activeRun.maxStderrBytes - activeRun.capturedStderr.count)
        if remaining > 0 {
            activeRun.capturedStderr.append(data.prefix(remaining))
        }
        self.activeRun = activeRun
    }

    private func stdoutDidFinish(runID: UUID) {
        guard var activeRun, activeRun.id == runID else { return }
        activeRun.stdoutFinished = true
        self.activeRun = activeRun
        finishIfReady(runID: runID)
    }

    private func stderrDidFinish(runID: UUID) {
        guard var activeRun, activeRun.id == runID else { return }
        activeRun.stderrFinished = true
        self.activeRun = activeRun
        finishIfReady(runID: runID)
    }

    private func processTerminated(runID: UUID, status: Int32) {
        guard var activeRun, activeRun.id == runID else { return }
        activeRun.terminationStatus = status
        self.activeRun = activeRun
        finishIfReady(runID: runID)
    }

    private func scheduleTimeout(for runID: UUID, duration: Duration?) {
        guard let duration, var activeRun, activeRun.id == runID else { return }
        activeRun.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.stop(runID: runID, failure: .timedOut)
        }
        self.activeRun = activeRun
    }

    private func stop(runID: UUID, failure: CLIProcessFailure) {
        guard var activeRun, activeRun.id == runID, activeRun.requestedFailure == nil else { return }
        activeRun.requestedFailure = failure
        self.activeRun = activeRun
        activeRun.process.terminate()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.interruptIfNeeded(runID: runID)
        }
    }

    private func interruptIfNeeded(runID: UUID) {
        guard let activeRun, activeRun.id == runID, activeRun.process.isRunning else { return }
        activeRun.process.interrupt()
    }

    private func finishIfReady(runID: UUID) {
        guard let activeRun,
              activeRun.id == runID,
              activeRun.terminationStatus != nil,
              activeRun.stdoutFinished,
              activeRun.stderrFinished else {
            return
        }

        if let failure = activeRun.requestedFailure {
            finish(runID: runID, throwing: failure)
        } else if activeRun.terminationStatus != 0 {
            finish(runID: runID, throwing: .helperExited)
        } else {
            finish(runID: runID, throwing: nil)
        }
    }

    private func finish(runID: UUID, throwing failure: CLIProcessFailure?) {
        guard let activeRun, activeRun.id == runID else { return }
        activeRun.timeoutTask?.cancel()
        activeRun.stdout.readabilityHandler = nil
        activeRun.stderr.readabilityHandler = nil
        self.activeRun = nil
        if let failure {
            activeRun.continuation.finish(throwing: failure)
        } else {
            activeRun.continuation.finish()
        }
    }
}
