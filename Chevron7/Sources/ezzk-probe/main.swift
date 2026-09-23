// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import Chevron7Kit

// Usage: ezzk-probe <login|time|numbers|consume|lookup|record> [evidence number]
//                   [--env test|production] [--name <person name>] [--ico <IČO>] [--at <ISO 8601 time>]
//                   [--purpose original|xml] [--out <file>]
// Credentials come from EZZK_LOGIN and EZZK_PASSWORD, otherwise from the Keychain item that
// Settings saved for the environment. They are never printed.
// numbers and consume allocate or consume evidence numbers, so they refuse production.
// record reads one of the signed-in person's own records (GetConversionRecord) and writes the
// returned object to --out; it changes nothing in EZZK.

setlinebuf(stdout)

let usage = "usage: ezzk-probe <login|time|numbers|consume|lookup|record> [number] [--env test|production] [--name N] [--ico I] [--at ISO] [--purpose original|xml] [--out FILE]\n"
let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(message.utf8))
    exit(code)
}

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

/// The first argument after the command that is neither an option nor an option value.
func positionalArgument() -> String? {
    var index = 1
    while index < arguments.count {
        if arguments[index].hasPrefix("--") {
            index += 2
            continue
        }
        return arguments[index]
    }
    return nil
}

guard let command = arguments.first else { fail(usage, code: 2) }

let environment: EZZKEnvironment
switch option("--env") ?? "test" {
case "test": environment = .sandbox
case "production": environment = .production
default: fail(usage, code: 2)
}

if (command == "numbers" || command == "consume") && environment == .production {
    fail("error: \(command) allocates or consumes evidence numbers and is refused on production\n", code: 2)
}

let person = EZZKPerson(corporateBodyFullName: option("--name") ?? "", ico: option("--ico") ?? "")
let number = positionalArgument()
let executionTime = option("--at").flatMap(EZZKSOAPDate.date(from:))
let client = EZZKSOAPClient(
    environment: environment,
    transport: URLSessionEZZKSOAPTransport(environment: environment),
    credentials: {
        let variables = ProcessInfo.processInfo.environment
        if let login = variables["EZZK_LOGIN"], let password = variables["EZZK_PASSWORD"],
           !login.isEmpty, !password.isEmpty {
            return EZZKSOAPCredentials(login: login, password: password)
        }
        return try EZZKSOAPCredentialStore().load(environment: environment)
    })

// Top-level code runs on the main actor and the semaphore blocks it, so the work must be detached.
let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    do {
        switch command {
        case "login":
            let account = try await client.logIn()
            print("Prihlásenie úspešné, účet: \(account)")
        case "time":
            print("Čas servera: \(EZZKSOAPDate.string(from: try await client.serverTime()))")
        case "numbers":
            let numbers = try await client.evidenceNumbers(for: person)
            print("Nespotrebované čísla (\(numbers.count)):")
            for value in numbers {
                print("  \(value)")
            }
        case "consume":
            guard let number else { fail(usage, code: 2) }
            try await client.consume(evidenceNumber: number, person: person)
            print("Spotrebované: \(number)")
        case "lookup":
            guard let number else { fail(usage, code: 2) }
            let lookup = try await client.publicRecord(evidenceNumber: number, executionTime: executionTime)
            print(lookup.isProcessed ? "Záznam je spracovaný." : "Záznam je evidovaný, ale nespracovaný.")
            if let info = lookup.info {
                print("Číslo: \(info.evidenceNumber)")
                print("Konverzia: \(info.executionTime.map(EZZKSOAPDate.string(from:)) ?? "-")")
                print("Prijaté: \(info.receiptTime.map(EZZKSOAPDate.string(from:)) ?? "-")")
                print("Osoba: \(info.personName ?? "-")")
                print("Pôvodný dokument: \(info.originalDocumentName ?? "-"), formát \(info.originalDocumentFormat ?? "-"), listov \(info.originalDocumentSheets.map(String.init) ?? "-")")
                print("Nový dokument: \(info.newDocumentName ?? "-"), formát \(info.newDocumentFormat ?? "-")")
            }
        case "record":
            guard let number, let out = option("--out") else { fail(usage, code: 2) }
            let purpose: EZZKRecordPurpose = option("--purpose") == "xml" ? .xml : .original
            let record = try await client.record(evidenceNumber: number, purpose: purpose,
                                                 executionTime: executionTime)
            print(record.lookup.isProcessed ? "Záznam je spracovaný." : "Záznam je evidovaný, ale nespracovaný.")
            if let object = record.object {
                try object.write(to: URL(fileURLWithPath: out))
                print("Objekt (\(object.count) B) uložený do \(out)")
            } else {
                print("EZZK nevrátilo žiadny objekt.")
            }
        default:
            fail(usage, code: 2)
        }
        exit(0)
    } catch {
        fail("error: \(error.localizedDescription)\n", code: 1)
    }
}
semaphore.wait()
