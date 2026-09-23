// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Identity
import Foundation

public struct EvidenceRecord: Codable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case draft = "Koncept"
        case awaitingNumber = "Čaká na evidenčné číslo"
        case readyToSign = "Pripravené na autorizáciu"
        case signed = "Autorizované (KEP)"
        case queuedForSubmission = "Vo fronte odoslania"
        case submitted = "Zapísané v CEZZK"
        case submissionFailed = "Odoslanie zlyhalo"
        case acceptedForProcessing = "Prijatý na spracovanie v EZZK"
        case processed = "Spracovaný v EZZK"
        case outcomeUnknown = "Výsledok odoslania neznámy"
        case rejected = "Odmietnutý v EZZK"
        case recordUnsigned = "Záznam nepodpísaný"
        case late = "Oneskorený"

        public var sfSymbol: String {
            switch self {
            case .draft: return "doc"
            case .awaitingNumber: return "number.square"
            case .readyToSign: return "checkmark.circle"
            case .signed: return "signature"
            case .queuedForSubmission: return "tray.and.arrow.up"
            case .submitted: return "checkmark.seal.fill"
            case .submissionFailed: return "exclamationmark.triangle.fill"
            case .acceptedForProcessing: return "tray.and.arrow.down.fill"
            case .processed: return "checkmark.circle.fill"
            case .outcomeUnknown: return "questionmark.circle.fill"
            case .rejected: return "xmark.seal.fill"
            case .recordUnsigned: return "square.and.pencil"
            case .late: return "clock.badge.exclamationmark.fill"
            }
        }

        public var progressIndex: Int {
            switch self {
            case .draft: return 0
            case .awaitingNumber: return 1
            case .readyToSign: return 2
            case .signed, .recordUnsigned: return 3
            case .queuedForSubmission, .submissionFailed, .outcomeUnknown, .rejected, .late: return 4
            case .submitted, .acceptedForProcessing: return 5
            case .processed: return 6
            }
        }

        /// Whether the record is somewhere in the EZZK submission pipeline
        /// (submitted but not yet resolved to a terminal, confirmed state).
        public var isSubmissionPendingState: Bool {
            switch self {
            case .signed, .queuedForSubmission, .submissionFailed, .outcomeUnknown, .late:
                return true
            default:
                return false
            }
        }
    }

    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var status: Status
    public var direction: ConversionDirection
    public var originalName: String
    public var newDocumentName: String
    public var evidenceNumber: String?
    public var fingerprintSHA256Hex: String
    public var attestationXML: String
    public var conversionTime: Date
    public var performingPersonName: String
    public var securityElementCount: Int
    public var totalPages: Int
    public var totalSheets: Int
    public var pdfFileName: String?
    public var formPack: FormPackStamp?
    public var securityReview: SecurityReviewStamp?
    public var ezzkMode: AppSettings.EZZKMode?
    public var evidenceNumberAllocatedAt: Date?
    /// Path to the signed record container, relative to the register folder
    /// (for example "records/<uuid>.asice"). Read with
    /// `LocalEvidenceStore.recordContainerData(for:)`.
    public var recordContainerPath: String?
    public var submittedAt: Date?
    public var submissionMessageID: String?
    public var ezzkResultCode: Int?
    public var ezzkResultDescription: String?
    public var lastLookupAt: Date?

    public var evidenceURI: String? {
        guard let evidenceNumber, !evidenceNumber.isEmpty else { return nil }
        let uri = ZakoCodelists.conversionRecordURI(evidenceNumber: evidenceNumber)
        return uri.isEmpty ? nil : uri
    }

    public static let submissionDeadlineInterval: TimeInterval = 24 * 3600

    public var submissionDeadline: Date {
        conversionTime.addingTimeInterval(Self.submissionDeadlineInterval)
    }

    public var isSubmissionPending: Bool {
        status.isSubmissionPendingState
    }

    public var isOverdue: Bool {
        isSubmissionPending && Date() > submissionDeadline
    }

    public func envelope() -> ConversionRecordEnvelope {
        ConversionRecordEnvelope(
            evidenceNumber: evidenceNumber ?? "",
            direction: direction,
            originalName: originalName,
            newDocumentName: newDocumentName,
            attestationXML: attestationXML,
            fingerprintSHA256Hex: fingerprintSHA256Hex,
            conversionTime: conversionTime,
            formPack: formPack,
            securityReview: securityReview)
    }

    public init(id: UUID = UUID(), createdAt: Date = Date(), status: Status,
                direction: ConversionDirection, originalName: String,
                newDocumentName: String, evidenceNumber: String?,
                fingerprintSHA256Hex: String, attestationXML: String,
                conversionTime: Date, performingPersonName: String,
                securityElementCount: Int, totalPages: Int, totalSheets: Int,
                 pdfFileName: String? = nil,
                 formPack: FormPackStamp? = nil,
                 securityReview: SecurityReviewStamp? = nil,
                 ezzkMode: AppSettings.EZZKMode? = nil,
                 evidenceNumberAllocatedAt: Date? = nil,
                 recordContainerPath: String? = nil,
                 submittedAt: Date? = nil,
                 submissionMessageID: String? = nil,
                 ezzkResultCode: Int? = nil,
                 ezzkResultDescription: String? = nil,
                 lastLookupAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.status = status
        self.direction = direction
        self.originalName = originalName
        self.newDocumentName = newDocumentName
        self.evidenceNumber = evidenceNumber
        self.fingerprintSHA256Hex = fingerprintSHA256Hex
        self.attestationXML = attestationXML
        self.conversionTime = conversionTime
        self.performingPersonName = performingPersonName
        self.securityElementCount = securityElementCount
        self.totalPages = totalPages
        self.totalSheets = totalSheets
        self.pdfFileName = pdfFileName
        self.formPack = formPack
        self.securityReview = securityReview
        self.ezzkMode = ezzkMode
        self.evidenceNumberAllocatedAt = evidenceNumberAllocatedAt
        self.recordContainerPath = recordContainerPath
        self.submittedAt = submittedAt
        self.submissionMessageID = submissionMessageID
        self.ezzkResultCode = ezzkResultCode
        self.ezzkResultDescription = ezzkResultDescription
        self.lastLookupAt = lastLookupAt
    }
}

public final class LocalEvidenceStore: @unchecked Sendable {
    private let folderURL: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "\(ProductIdentity.bundleIdentifier).evidence")
    public private(set) var records: [EvidenceRecord] = []

    public init(directory: URL? = nil) {
        let root = directory ?? ProductIdentity.applicationSupportDirectory()
        let base = root.appendingPathComponent("Evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.folderURL = base
        self.fileURL = base.appendingPathComponent("register.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder.standard.decode([EvidenceRecord].self, from: data) {
            self.records = loaded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func upsert(_ record: EvidenceRecord) {
        queue.sync {
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index] = record
            } else {
                records.insert(record, at: 0)
            }
            persistLocked()
        }
    }

    public func delete(id: UUID) {
        queue.sync {
            records.removeAll { $0.id == id }
            persistLocked()
        }
    }

    public func record(id: UUID) -> EvidenceRecord? {
        queue.sync { records.first { $0.id == id } }
    }

    public func pendingSubmission() -> [EvidenceRecord] {
        queue.sync {
            records.filter { $0.status == .queuedForSubmission || $0.status == .submissionFailed }
        }
    }

    /// Writes the signed record container (an ASiC-E `.asice`) under `records/`
    /// inside the register folder, atomically, and returns its path relative to
    /// that folder (suitable for `EvidenceRecord.recordContainerPath`).
    public func storeRecordContainer(_ data: Data, for id: UUID) throws -> String {
        let recordsFolder = folderURL.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: recordsFolder, withIntermediateDirectories: true)
        let relativePath = "records/\(id.uuidString).asice"
        let destination = folderURL.appendingPathComponent(relativePath)
        try data.write(to: destination, options: [.atomic])
        return relativePath
    }

    /// Reads back the container stored by `storeRecordContainer(_:for:)`, resolving
    /// `record.recordContainerPath` relative to the register folder.
    public func recordContainerData(for record: EvidenceRecord) -> Data? {
        guard let path = record.recordContainerPath else { return nil }
        return try? Data(contentsOf: folderURL.appendingPathComponent(path))
    }

    public func exportCSV() -> String {
        queue.sync {
            var rows = ["Evidenčné číslo;Dátum konverzie;Pôvodný dokument;Nový dokument;Strany;Listy;Prvky;SHA-256;Stav;Osoba"]
            for record in records {
                let fields = [
                    record.evidenceNumber ?? "",
                    Self.csvDate(record.conversionTime),
                    Self.escapeCSV(record.originalName),
                    Self.escapeCSV(record.newDocumentName),
                    "\(record.totalPages)",
                    "\(record.totalSheets)",
                    "\(record.securityElementCount)",
                    record.fingerprintSHA256Hex,
                    record.status.rawValue,
                    Self.escapeCSV(record.performingPersonName)
                ]
                rows.append(fields.joined(separator: ";"))
            }
            return rows.joined(separator: "\r\n") + "\r\n"
        }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder.pretty.encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    public static func csvDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func escapeCSV(_ value: String) -> String {
        value.contains(";") || value.contains("\"") || value.contains("\n")
            ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            : value
    }
}

public extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var standard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
