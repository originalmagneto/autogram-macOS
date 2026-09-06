import Foundation
import Darwin

enum QuickActionRunnerError: LocalizedError {
    case invalidArguments(String)
    case missingHelper
    case invalidPIN
    case machineRequestFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): message
        case .missingHelper: "Autogram macOS helper was not found."
        case .invalidPIN: "The signing PIN could not be read."
        case .machineRequestFailed: "Autogram macOS signing helper did not complete the request."
        }
    }
}

private enum HelperTerminalEvent {
    case completed
    case failed
}

private final class HelperTerminationController {
    // Process.terminate() sends SIGTERM to this local child. SIGTERM's default action is
    // immediate termination, so 100 ms is only one local signal-delivery grace period,
    // not a timeout for signing or any other helper work.
    private let terminationGrace = DispatchTimeInterval.milliseconds(100)
    private let processExited = DispatchSemaphore(value: 0)
    private let closeReaders: () -> Void
    private let lock = NSLock()
    private var terminalTerminationRequested = false

    init(closeReaders: @escaping () -> Void) {
        self.closeReaders = closeReaders
    }

    func terminateAfterTerminalEvent(_ process: Process) {
        lock.lock()
        guard !terminalTerminationRequested else {
            lock.unlock()
            return
        }
        terminalTerminationRequested = true
        lock.unlock()

        if process.isRunning {
            process.terminate()
        } else {
            closeReaders()
        }

        DispatchQueue.global().async { [self] in
            if processExited.wait(timeout: .now() + terminationGrace) == .timedOut,
               process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    func processDidExit() {
        lock.lock()
        let shouldCloseReaders = terminalTerminationRequested
        lock.unlock()
        if shouldCloseReaders {
            closeReaders()
        }
        processExited.signal()
    }
}

private final class HelperOutputCollector {
    private let terminalEventHandler: () -> Void
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()
    private var pendingOutput = Data()
    private var terminalEvent: HelperTerminalEvent?

    init(terminalEventHandler: @escaping () -> Void) {
        self.terminalEventHandler = terminalEventHandler
    }

    func appendStandardOutput(_ data: Data) {
        var shouldTerminate = false
        lock.lock()
        standardOutput.append(data)
        pendingOutput.append(data)
        while let newline = pendingOutput.firstIndex(of: 0x0A) {
            let line = pendingOutput.prefix(upTo: newline)
            pendingOutput.removeSubrange(...newline)
            guard terminalEvent == nil,
                  let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            switch event["type"] as? String {
            case "session.completed":
                terminalEvent = .completed
                shouldTerminate = true
            case "session.failed":
                terminalEvent = .failed
                shouldTerminate = true
            default:
                break
            }
        }
        lock.unlock()

        if shouldTerminate {
            terminalEventHandler()
        }
    }

    func appendStandardError(_ data: Data) {
        lock.lock()
        standardError.append(data)
        lock.unlock()
    }

    func result() -> (standardOutput: Data, standardError: Data, terminalEvent: HelperTerminalEvent?) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError, terminalEvent)
    }
}

struct QuickActionRequest {
    enum Operation: String {
        case certificates = "CERTIFICATES"
        case sign = "SIGN"
    }

    let operation: Operation
    let driver: String
    let certificate: String?
    let source: String?
    let target: String?
    let signatureLevel: String?
    let timestampServer: String?

    private init(
        operation: Operation,
        driver: String,
        certificate: String?,
        source: String?,
        target: String?,
        signatureLevel: String?,
        timestampServer: String?
    ) {
        self.operation = operation
        self.driver = driver
        self.certificate = certificate
        self.source = source
        self.target = target
        self.signatureLevel = signatureLevel
        self.timestampServer = timestampServer
    }

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw QuickActionRunnerError.invalidArguments("Unsupported option: \(argument)")
            }
            guard argument == "--pin-stdin" else {
                guard index + 1 < arguments.count else {
                    throw QuickActionRunnerError.invalidArguments("Missing value for \(argument)")
                }
                values[argument] = arguments[index + 1]
                index += 2
                continue
            }
            values[argument] = "true"
            index += 1
        }

        guard values["--pin-stdin"] == "true",
              let operationValue = values["--operation"],
              let operation = Operation(rawValue: operationValue),
              let driver = values["--driver"], !driver.isEmpty
        else {
            throw QuickActionRunnerError.invalidArguments("A machine operation, signing driver, and PIN on standard input are required.")
        }

        switch operation {
        case .certificates:
            self = QuickActionRequest(
                operation: operation,
                driver: driver,
                certificate: nil,
                source: nil,
                target: nil,
                signatureLevel: nil,
                timestampServer: nil
            )
        case .sign:
            guard let certificate = values["--certificate"], !certificate.isEmpty,
                  let source = values["--source"], !source.isEmpty,
                  let target = values["--target"], !target.isEmpty,
                  let signatureLevel = values["--signature-level"], !signatureLevel.isEmpty,
                  let timestampServer = values["--tsa-server"], !timestampServer.isEmpty
            else {
                throw QuickActionRunnerError.invalidArguments("Certificate, source, target, signature level, and timestamp server are required for signing.")
            }
            self = QuickActionRequest(
                operation: operation,
                driver: driver,
                certificate: certificate,
                source: source,
                target: target,
                signatureLevel: signatureLevel,
                timestampServer: timestampServer
            )
        }
    }
}

@main
struct AutogramQuickActionRunner {
    static func main() {
        do {
            let request = try QuickActionRequest(arguments: Array(CommandLine.arguments.dropFirst()))
            let result = try run(request)
            if request.operation == .certificates {
                writeCertificateList(from: result.standardOutput)
            } else {
                FileHandle.standardOutput.write(result.standardOutput)
            }
            FileHandle.standardError.write(result.standardError)
            guard result.terminalEvent == .completed else {
                throw QuickActionRunnerError.machineRequestFailed
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ request: QuickActionRequest) throws -> (standardOutput: Data, standardError: Data, terminalEvent: HelperTerminalEvent?) {
        var pin = try readPIN()
        defer { pin.removeAll(keepingCapacity: false) }
        var machineRequest = try requestData(for: request, pin: pin)
        defer { machineRequest.removeAll(keepingCapacity: false) }

        let process = Process()
        process.executableURL = try helperURL()
        process.arguments = [
            "--cli",
            "--machine-readable",
            "--protocol-version", "1",
            "--operation", request.operation.rawValue,
        ]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        let terminationController = HelperTerminationController {
            output.fileHandleForReading.closeFile()
            error.fileHandleForReading.closeFile()
        }
        process.terminationHandler = { terminatedProcess in
            terminationController.processDidExit()
        }
        try process.run()

        let collector = HelperOutputCollector {
            terminationController.terminateAfterTerminalEvent(process)
        }
        let drainGroup = DispatchGroup()
        drainGroup.enter()
        DispatchQueue.global().async {
            defer { drainGroup.leave() }
            while true {
                let data = output.fileHandleForReading.availableData
                guard !data.isEmpty else { return }
                collector.appendStandardOutput(data)
            }
        }
        drainGroup.enter()
        DispatchQueue.global().async {
            defer { drainGroup.leave() }
            while true {
                let data = error.fileHandleForReading.availableData
                guard !data.isEmpty else { return }
                collector.appendStandardError(data)
            }
        }

        try input.fileHandleForWriting.write(contentsOf: machineRequest)
        input.fileHandleForWriting.closeFile()
        drainGroup.wait()
        process.waitUntilExit()
        return collector.result()
    }

    private static func readPIN() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard var pin = String(data: data, encoding: .utf8) else {
            throw QuickActionRunnerError.invalidPIN
        }
        while pin.last?.isNewline == true {
            pin.removeLast()
        }
        return pin
    }

    private static func requestData(for request: QuickActionRequest, pin: String) throws -> Data {
        let payload: [String: Any]
        switch request.operation {
        case .certificates:
            payload = ["driver": request.driver, "pin": pin]
        case .sign:
            payload = [
                "driver": request.driver,
                "certificateSerial": request.certificate!,
                "pin": pin,
                "signatureLevel": request.signatureLevel!,
                "timestamp": ["required": true, "servers": [request.timestampServer!]],
                "files": [["id": "file-1", "source": request.source!, "target": request.target!]],
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1,
            "requestId": "autogram-quick-action",
            "operation": request.operation.rawValue,
            "payload": payload,
        ], options: [])
    }

    private static func helperURL() throws -> URL {
        let runnerURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let helper = runnerURL.deletingLastPathComponent().appending(path: "AutogramCLI-arm64")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw QuickActionRunnerError.missingHelper
        }
        return helper
    }

    private static func writeCertificateList(from output: Data) {
        for event in events(in: output) where event["type"] as? String == "certificates.available" {
            guard let payload = event["payload"] as? [String: Any],
                  let certificates = payload["certificates"] as? [[String: Any]]
            else { continue }
            for certificate in certificates {
                guard let serial = certificate["serial"] as? String, !serial.isEmpty else { continue }
                let commonName = (certificate["commonName"] as? String ?? "")
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                FileHandle.standardOutput.write(Data("AUTOGRAM_KEY\t\(serial)\t\(commonName)\n".utf8))
            }
        }
    }

    private static func events(in output: Data) -> [[String: Any]] {
        String(decoding: output, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                guard let data = line.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return event
            }
    }
}
