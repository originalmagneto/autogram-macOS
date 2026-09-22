import Chevron7Identity
import Foundation
import os

public struct EZZKSOAPFault: Equatable, Sendable {
    public var subcode: String
    public var reason: String
}

public struct EZZKLoginOutcome: Equatable, Sendable {
    public var errorCode: String?
    public var token: String?
    public var accountName: String?
}

public struct EZZKRecordInfo: Equatable, Sendable {
    public var evidenceNumber: String
    public var executionTime: Date?
    public var receiptTime: Date?
    public var personName: String?
    public var originalDocumentName: String?
    public var originalDocumentFormat: String?
    public var originalDocumentSheets: Int?
    public var newDocumentName: String?
    public var newDocumentFormat: String?
    public var newDocumentSheets: Int?
}

public struct EZZKRecordLookup: Equatable, Sendable {
    /// False for result code 1: recorded, but EZZK has not finished processing it.
    public var isProcessed: Bool
    public var info: EZZKRecordInfo?

    public init(isProcessed: Bool, info: EZZKRecordInfo?) {
        self.isProcessed = isProcessed
        self.info = info
    }
}

enum EZZKSOAPReply {
    case document(XMLDocument)
    case authenticationRequired
}

/// Reads EZZK replies by local element name: WCF moves namespace prefixes between
/// replies, and test and production place some fields in different namespaces.
enum EZZKSOAPResponseParser {
    static let unauthorizedResultCode = 101
    static let serviceNotInitializedReason = "service implementation object was not initialized"

    /// `DeserializationFailed` and `ActionMismatch` are application defects (Autogram sent a
    /// malformed or mismatched request), never a normal user-facing condition, so they are
    /// logged for diagnosis. Only the fault subcode (public) and reason text (private) are
    /// logged, never the fault detail or a stack trace.
    private static let logger = Logger(subsystem: ProductIdentity.bundleIdentifier, category: "EZZK")

    static func reply(data: Data, statusCode: Int) throws -> EZZKSOAPReply {
        guard let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) else {
            throw statusCode == 200 ? EZZKError.invalidResponse : EZZKError.networkFailure("HTTP \(statusCode)")
        }
        if let fault = fault(in: document) {
            // Without a valid token cookie the service cannot create its implementation object.
            if fault.subcode == "InternalServiceFault",
               fault.reason.localizedCaseInsensitiveContains(serviceNotInitializedReason) {
                return .authenticationRequired
            }
            if fault.subcode == "DeserializationFailed" || fault.subcode == "ActionMismatch" {
                logger.error("Application defect: SOAP fault \(fault.subcode, privacy: .public) - \(fault.reason, privacy: .private)")
                throw EZZKError.invalidRequest(fault.subcode)
            }
            throw EZZKError.serviceRejected(code: statusCode, message: fault.reason)
        }
        guard statusCode == 200 else { throw EZZKError.networkFailure("HTTP \(statusCode)") }
        if resultCode(in: document) == unauthorizedResultCode {
            return .authenticationRequired
        }
        return .document(document)
    }

    static func fault(in document: XMLDocument) -> EZZKSOAPFault? {
        let faults = (try? document.nodes(
            forXPath: "/*[local-name()='Envelope']/*[local-name()='Body']/*[local-name()='Fault']")) ?? []
        guard !faults.isEmpty else { return nil }
        let subcodeValue = strings("//*[local-name()='Subcode']/*[local-name()='Value']", in: document).first ?? ""
        let subcode = subcodeValue.split(separator: ":").last.map(String.init) ?? subcodeValue
        let reason = strings("//*[local-name()='Reason']/*[local-name()='Text']", in: document).first ?? ""
        return EZZKSOAPFault(subcode: subcode, reason: reason)
    }

    static func resultCode(in document: XMLDocument) -> Int? {
        strings("//*[local-name()='Result']/*[local-name()='Code']", in: document).first
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Returns the result code when it is accepted; otherwise throws the server's own text.
    @discardableResult
    static func requireSuccess(_ document: XMLDocument, accepting accepted: Set<Int> = [0]) throws -> Int {
        guard let code = resultCode(in: document) else { throw EZZKError.invalidResponse }
        guard accepted.contains(code) else {
            let description = strings("//*[local-name()='Result']/*[local-name()='Description']", in: document).first ?? ""
            throw EZZKError.serviceRejected(code: code, message: description)
        }
        return code
    }

    static func login(in document: XMLDocument) -> EZZKLoginOutcome {
        EZZKLoginOutcome(
            errorCode: text("ErrorCode", in: document),
            token: text("TokenDescriptor", in: document),
            accountName: strings("//*[local-name()='Account']/*[local-name()='Name']", in: document)
                .first.flatMap(nonEmpty))
    }

    static func evidenceNumbers(in document: XMLDocument) -> [String] {
        strings("//*[local-name()='ConversionRecordEvidenceNumberList']/*[local-name()='ConversionRecordEvidenceNumber']",
                in: document).compactMap(nonEmpty)
    }

    static func recordInfo(in document: XMLDocument) -> EZZKRecordInfo? {
        let xpath = "//*[local-name()='Result']//*[local-name()='Data'][*[local-name()='ConversionRecordEvidenceNumber']]"
        guard let data = (try? document.nodes(forXPath: xpath))?.first as? XMLElement,
              let number = child("ConversionRecordEvidenceNumber", of: data) else { return nil }
        return EZZKRecordInfo(
            evidenceNumber: number,
            executionTime: child("ConversionExecutionDateTime", of: data).flatMap(EZZKSOAPDate.date(from:)),
            receiptTime: child("ReceiptDate", of: data).flatMap(EZZKSOAPDate.date(from:)),
            personName: child("PersonPerformingConversion", of: data),
            originalDocumentName: child("OriginalDocumentName", of: data),
            originalDocumentFormat: child("OriginalDocumentFormat", of: data),
            originalDocumentSheets: child("OriginalDocumentNumberOfSheets", of: data).flatMap { Int($0) },
            newDocumentName: child("NewDocumentName", of: data),
            newDocumentFormat: child("NewDocumentFormat", of: data),
            newDocumentSheets: child("NewDocumentNumberOfSheets", of: data).flatMap { Int($0) })
    }

    static func objectData(in document: XMLDocument) -> Data? {
        strings("//*[local-name()='ObjectData']/*[local-name()='Data']", in: document).first
            .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
    }

    private static func strings(_ xpath: String, in document: XMLDocument) -> [String] {
        ((try? document.nodes(forXPath: xpath)) ?? []).compactMap(\.stringValue)
    }

    private static func text(_ localName: String, in document: XMLDocument) -> String? {
        strings("//*[local-name()='\(localName)']", in: document).first.flatMap(nonEmpty)
    }

    private static func child(_ localName: String, of element: XMLElement) -> String? {
        element.children?.first { $0.localName == localName }?.stringValue.flatMap(nonEmpty)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
