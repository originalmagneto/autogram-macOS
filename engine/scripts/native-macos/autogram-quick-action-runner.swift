import Foundation
import Darwin

enum QuickActionRunnerError: LocalizedError {
    case invalidArguments(String)
    case missingHelper
    case invalidPIN
    case machineRequestFailed(HelperFailure)
    case helperExitedWithoutResult(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): message
        case .missingHelper: "Pomocný program Autogram macOS (AutogramCLI-arm64) sa nenašiel."
        case .invalidPIN: "Podpisový PIN sa nepodarilo načítať."
        case .machineRequestFailed(let failure): failure.userMessage
        case .helperExitedWithoutResult(let status):
            "Podpisový engine Autogramu skončil (stav \(status)) bez toho, aby oznámil výsledok."
        }
    }
}

/// Payload of a `session.failed` event. The engine speaks English over the machine protocol;
/// the runner translates known codes for the Finder dialog and keeps the engine text for
/// codes it does not know, so the actual cause (missing card, wrong PIN, ...) is always named.
struct HelperFailure {
    let code: String
    let message: String
    let recovery: String?
    let retryable: Bool

    init(payload: [String: Any]) {
        code = payload["code"] as? String ?? "UNKNOWN"
        message = payload["fallbackMessage"] as? String ?? "The machine request could not be completed."
        recovery = payload["recovery"] as? String
        retryable = payload["retryable"] as? Bool ?? false
    }

    var userMessage: String {
        if let slovak = Self.slovakMessages[code] {
            return "Autogram: \(slovak) [\(code)]"
        }
        var text = "Autogram: podpisový engine požiadavku nedokončil [\(code)]: \(message)"
        if let recovery, !recovery.isEmpty {
            text += " \(recovery)"
        }
        if retryable {
            text += " Skúste znova."
        }
        return text
    }

    private static let slovakMessages: [String: String] = [
        "TOKEN_NOT_PRESENT": "V čítačke nie je karta pre zvolený ovládač. Vložte kartu, počkajte na kontrolku čítačky a skúste znova.",
        "TOKEN_NOT_RECOGNIZED": "Karta v čítačke nezodpovedá zvolenému ovládaču. Zvoľte ovládač podľa karty (eID klient alebo I.CA SecureStore) a skúste znova.",
        "PIN_INCORRECT": "Zadaný PIN nebol prijatý. Overte PIN a skúste znova.",
        "PIN_LOCKED": "PIN karty je zablokovaný. Odomknite ho PUK kódom cez nástroj výrobcu karty.",
        "OPERATION_CANCELLED": "Operácia s kartou bola zrušená. Skúste znova.",
        "DRIVER_NOT_FOUND": "Zvolený ovládač karty nie je nainštalovaný alebo sa nenašiel.",
        "DRIVER_UNAVAILABLE": "Ovládač karty sa nepodarilo načítať. Skontrolujte inštaláciu eID klienta alebo I.CA SecureStore.",
        "CERTIFICATE_NOT_FOUND": "Zvolený certifikát sa na karte nenašiel. Obnovte zoznam certifikátov.",
        "CERTIFICATE_AMBIGUOUS": "Zvolenému certifikátu zodpovedá viac kľúčov na karte. Obnovte zoznam certifikátov.",
        "SIGNING_UNAVAILABLE": "Podpisovanie nie je dostupné. Skontrolujte kartu, ovládač a pripojenie na internet.",
        "SIGNING_FAILED": "Podpis sa nepodarilo vytvoriť.",
        "TRUSTED_LIST_UNAVAILABLE": "Dôveryhodný zoznam certifikačných autorít nie je dostupný. Skontrolujte pripojenie na internet.",
        "TIMESTAMP_FAILED": "Nepodarilo sa získať kvalifikovanú časovú pečiatku (TSA).",
        "TIMESTAMP_QUALIFICATION_FAILED": "Časová pečiatka nie je kvalifikovaná. Skontrolujte adresu TSA servera.",
        "TSA_REQUIRED": "Chýba adresa TSA servera pre časovú pečiatku.",
        "OUTPUT_TARGET_EXISTS": "Cieľový súbor už existuje.",
        "OUTPUT_WRITE_FAILED": "Podpísaný súbor sa nepodarilo zapísať.",
        "OUTPUT_VALIDATION_FAILED": "Engine odmietol výsledok podpisu (výstupná validácia).",
        "OUTPUT_CLEANUP_FAILED": "Dočasné súbory podpisu sa nepodarilo odstrániť.",
        "MACHINE_PLATFORM_UNSUPPORTED": "Táto platforma nie je podporovaná (vyžaduje sa Apple Silicon).",
        "PROTOCOL_INVALID_REQUEST": "Požiadavka pre podpisový engine je neplatná (chyba Quick Action skriptu).",
    ]
}

private enum HelperTerminalEvent {
    case completed
    case failed(HelperFailure)
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
                terminalEvent = .failed(HelperFailure(payload: event["payload"] as? [String: Any] ?? [:]))
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
            switch result.terminalEvent {
            case .completed:
                break
            case .failed(let failure):
                throw QuickActionRunnerError.machineRequestFailed(failure)
            case nil:
                throw QuickActionRunnerError.helperExitedWithoutResult(result.terminationStatus)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private struct HelperRunResult {
        let standardOutput: Data
        let standardError: Data
        let terminalEvent: HelperTerminalEvent?
        let terminationStatus: Int32
    }

    private static func run(_ request: QuickActionRequest) throws -> HelperRunResult {
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
        let collected = collector.result()
        return HelperRunResult(standardOutput: collected.standardOutput,
                               standardError: collected.standardError,
                               terminalEvent: collected.terminalEvent,
                               terminationStatus: process.terminationStatus)
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
