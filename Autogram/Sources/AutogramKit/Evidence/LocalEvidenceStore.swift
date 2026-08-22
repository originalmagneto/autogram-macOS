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

        public var sfSymbol: String {
            switch self {
            case .draft: return "doc"
            case .awaitingNumber: return "number.square"
            case .readyToSign: return "checkmark.circle"
            case .signed: return "signature"
            case .queuedForSubmission: return "tray.and.arrow.up"
            case .submitted: return "checkmark.seal.fill"
            case .submissionFailed: return "exclamationmark.triangle.fill"
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

    public init(id: UUID = UUID(), createdAt: Date = Date(), status: Status,
                direction: ConversionDirection, originalName: String,
                newDocumentName: String, evidenceNumber: String?,
                fingerprintSHA256Hex: String, attestationXML: String,
                conversionTime: Date, performingPersonName: String,
                securityElementCount: Int, totalPages: Int, totalSheets: Int,
                pdfFileName: String? = nil) {
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
    }
}

public final class LocalEvidenceStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "sk.autogram.evidence")
    public private(set) var records: [EvidenceRecord] = []

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Autogram/Evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
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
