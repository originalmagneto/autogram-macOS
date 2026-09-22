// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public struct EZZKPerson: Equatable, Sendable {
    public var corporateBodyFullName: String
    public var ico: String

    public init(corporateBodyFullName: String, ico: String) {
        self.corporateBodyFullName = corporateBodyFullName
        self.ico = ico
    }

    /// EZZK needs both values to identify the person performing the conversion.
    public var isComplete: Bool {
        !corporateBodyFullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ico.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum EZZKRecordPurpose: Int, Sendable {
    case original = 1
    case xml = 2
}

/// A signed record container for `ReceiveConversionRecord`.
public struct EZZKRecordAttachment: Equatable, Sendable {
    public var evidenceNumber: String
    public var mimeType: String
    public var data: Data

    public init(evidenceNumber: String, mimeType: String, data: Data) {
        self.evidenceNumber = evidenceNumber
        self.mimeType = mimeType
        self.data = data
    }
}

public struct EZZKSOAPRequest: Sendable {
    public enum Endpoint: Sendable {
        case login
        case service
    }

    public let endpoint: Endpoint
    public let operation: String
    public let action: String
    /// The operation element with every namespace it uses declared on itself, so it
    /// validates on its own against the XSD snapshot.
    public let body: String
    public let requiresAuthentication: Bool
    /// EZZK may have acted on the request even when no reply arrived.
    public let isConsequential: Bool

    public func url(in environment: EZZKEnvironment) -> URL {
        switch endpoint {
        case .login: environment.soapLoginURL
        case .service: environment.soapServiceURL
        }
    }

    public func urlRequest(in environment: EZZKEnvironment, messageID: UUID = UUID()) -> URLRequest {
        let target = url(in: environment)
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/soap+xml; charset=utf-8; action=\"\(action)\"",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(EZZKSOAPEnvelope.wrap(body: body, action: action, to: target,
                                                      messageID: messageID).utf8)
        return request
    }
}

extension EZZKSOAPRequest {
    static let serviceActionPrefix = "http://www.ditec.sk/IEZZKService/IEZZKService/"

    public static func login(login: String, password: String) -> EZZKSOAPRequest {
        let body = [
            "<core:InputMessageOf_LogInInput xmlns:core=\"\(EZZKSOAPNamespace.iamCore)\" xmlns:i=\"\(EZZKSOAPNamespace.instance)\">",
            "<core:Content i:type=\"core:LogInInputAuthentication\">",
            "<core:InputData i:type=\"core:TokenInputData\"><core:ApplicationId>EZZK</core:ApplicationId></core:InputData>",
            "<core:AuthenticationInput i:type=\"core:PasswordInput\">",
            "<core:Login>\(EZZKXML.escape(login))</core:Login>",
            "<core:Password>\(EZZKXML.escape(password))</core:Password>",
            "</core:AuthenticationInput>",
            "</core:Content>",
            "</core:InputMessageOf_LogInInput>"
        ].joined()
        return EZZKSOAPRequest(endpoint: .login, operation: "LogIn",
                               action: "http://ditec/2017/06/iam/core/ILogInService/LogIn",
                               body: body, requiresAuthentication: false, isConsequential: false)
    }

    /// `GetOptions` needs no login; the HTTP `Date` header of its reply is the server time.
    public static func serverTime() -> EZZKSOAPRequest {
        service("GetOptions", body: "<iez:GetOptions xmlns:iez=\"\(EZZKSOAPNamespace.service)\"/>",
                authenticated: false, consequential: false)
    }

    public static func evidenceNumbers(person: EZZKPerson, messageID: UUID = UUID(),
                                       objectID: UUID = UUID()) -> EZZKSOAPRequest {
        let body = [
            "<iez:GetConversionRecordEvidenceNumber xmlns:iez=\"\(EZZKSOAPNamespace.service)\" xmlns:w=\"\(EZZKSOAPNamespace.evidenceNumber)\" xmlns:d=\"\(EZZKSOAPNamespace.dol)\" xmlns:i=\"\(EZZKSOAPNamespace.instance)\">",
            "<iez:request><w:Container>",
            "<w:EvidenceNumberAmount i:nil=\"true\"/>",
            "<w:MessageId>\(messageID.uuidString.lowercased())</w:MessageId>",
            "<w:Object>", formObjectHeader(id: objectID), personData(person), "</w:Object>",
            "</w:Container></iez:request>",
            "</iez:GetConversionRecordEvidenceNumber>"
        ].joined()
        return service("GetConversionRecordEvidenceNumber", body: body, authenticated: true, consequential: true)
    }

    /// A nil number asks EZZK to consume the person's oldest unconsumed number.
    public static func consume(evidenceNumber: String?, person: EZZKPerson, messageID: UUID = UUID(),
                               objectID: UUID = UUID()) -> EZZKSOAPRequest {
        let number = evidenceNumber.map {
            "<d:ConversionRecordEvidenceNumber>\(EZZKXML.escape($0))</d:ConversionRecordEvidenceNumber>"
        } ?? "<d:ConversionRecordEvidenceNumber i:nil=\"true\"/>"
        let body = [
            "<iez:ConsumeConversionRecordEvidenceNumber xmlns:iez=\"\(EZZKSOAPNamespace.service)\" xmlns:w=\"\(EZZKSOAPNamespace.consume)\" xmlns:d=\"\(EZZKSOAPNamespace.dol)\" xmlns:i=\"\(EZZKSOAPNamespace.instance)\">",
            "<iez:request><w:Container>",
            "<w:MessageId>\(messageID.uuidString.lowercased())</w:MessageId>",
            "<w:Object>", formObjectHeader(id: objectID), number, personData(person), "</w:Object>",
            "</w:Container></iez:request>",
            "</iez:ConsumeConversionRecordEvidenceNumber>"
        ].joined()
        return service("ConsumeConversionRecordEvidenceNumber", body: body, authenticated: true, consequential: true)
    }

    /// `GetConversionRecordInformationPurpose`: public lookup, no login.
    public static func publicRecord(evidenceNumber: String, executionTime: Date?, at timestamp: Date,
                                    messageID: UUID = UUID(), objectID: UUID = UUID()) -> EZZKSOAPRequest {
        let body = [
            "<iez:GetConversionRecordInformationPurpose xmlns:iez=\"\(EZZKSOAPNamespace.service)\" xmlns:d=\"\(EZZKSOAPNamespace.dol)\">",
            "<iez:request><d:Container>",
            "<d:MessageId>\(messageID.uuidString.lowercased())</d:MessageId>",
            "<d:Object>", formObjectHeader(id: objectID),
            "<d:Data>", recordQuery(evidenceNumber: evidenceNumber, executionTime: executionTime, timestamp: timestamp), "</d:Data>",
            "</d:Object>",
            "</d:Container></iez:request>",
            "</iez:GetConversionRecordInformationPurpose>"
        ].joined()
        return service("GetConversionRecordInformationPurpose", body: body, authenticated: false, consequential: false)
    }

    /// `GetConversionRecord`: the person's own record, with the original object when purpose is 1.
    public static func record(evidenceNumber: String, purpose: EZZKRecordPurpose, executionTime: Date?,
                              at timestamp: Date, messageID: UUID = UUID(),
                              objectID: UUID = UUID()) -> EZZKSOAPRequest {
        let body = [
            "<iez:GetConversionRecord xmlns:iez=\"\(EZZKSOAPNamespace.service)\" xmlns:d=\"\(EZZKSOAPNamespace.dol)\" xmlns:r=\"\(EZZKSOAPNamespace.record)\">",
            "<iez:request><d:Container>",
            "<d:MessageId>\(messageID.uuidString.lowercased())</d:MessageId>",
            "<d:Object>", formObjectHeader(id: objectID),
            "<d:Data>", recordQuery(evidenceNumber: evidenceNumber, executionTime: executionTime, timestamp: timestamp),
            "<r:Purpose>\(purpose.rawValue)</r:Purpose>", "</d:Data>",
            "</d:Object>",
            "</d:Container></iez:request>",
            "</iez:GetConversionRecord>"
        ].joined()
        return service("GetConversionRecord", body: body, authenticated: true, consequential: false)
    }

    public static let receiveOperation = "ReceiveConversionRecord"

    public static func receive(records: [EZZKRecordAttachment], person: EZZKPerson, messageID: UUID = UUID(),
                               objectID: UUID = UUID()) -> EZZKSOAPRequest {
        let attachments = records.map { record in
            [
                "<d:ObjectOfstring>",
                "<d:Class>ATTACHMENT</d:Class>",
                "<d:Encoding>Base64</d:Encoding>",
                "<d:Id>\(EZZKXML.escape(record.evidenceNumber))</d:Id>",
                "<d:IsSigned>true</d:IsSigned>",
                "<d:Mimetype>\(EZZKXML.escape(record.mimeType))</d:Mimetype>",
                "<d:Data>\(record.data.base64EncodedString())</d:Data>",
                "</d:ObjectOfstring>"
            ].joined()
        }.joined()
        let ico = person.ico.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = [
            "<iez:ReceiveConversionRecord xmlns:iez=\"\(EZZKSOAPNamespace.service)\" xmlns:w=\"\(EZZKSOAPNamespace.receive)\" xmlns:d=\"\(EZZKSOAPNamespace.dol)\" xmlns:i=\"\(EZZKSOAPNamespace.instance)\">",
            "<iez:request><w:Container>",
            "<w:MessageId>\(messageID.uuidString.lowercased())</w:MessageId>",
            "<w:Object>", formObjectHeader(id: objectID), personData(person), "</w:Object>",
            "<w:ObjectDataList>", attachments, "</w:ObjectDataList>",
            "<w:SenderId>ico://sk/\(EZZKXML.escape(ico))</w:SenderId>",
            "</w:Container></iez:request>",
            "</iez:ReceiveConversionRecord>"
        ].joined()
        return service(receiveOperation, body: body, authenticated: true, consequential: true)
    }

    private static func service(_ operation: String, body: String, authenticated: Bool,
                                consequential: Bool) -> EZZKSOAPRequest {
        EZZKSOAPRequest(endpoint: .service, operation: operation, action: serviceActionPrefix + operation,
                        body: body, requiresAuthentication: authenticated, isConsequential: consequential)
    }

    /// Shared object elements; they live in the base `Ditec.IOM.EZZK.Dol` namespace.
    private static func formObjectHeader(id: UUID) -> String {
        "<d:Class>FORM</d:Class><d:Encoding>XML</d:Encoding><d:Id>\(id.uuidString.lowercased())</d:Id><d:IsSigned>false</d:IsSigned><d:Mimetype>application/xml</d:Mimetype>"
    }

    /// Inherited `ZiadostVypis` fields also live in the base namespace, not the operation
    /// namespace the manual shows; the service rejects the manual's form.
    private static func recordQuery(evidenceNumber: String, executionTime: Date?, timestamp: Date) -> String {
        let execution = executionTime.map {
            "<d:ConversionExecutionDateTime>\(EZZKSOAPDate.string(from: $0))</d:ConversionExecutionDateTime>"
        } ?? ""
        return execution
            + "<d:ConversionRecordEvidenceNumber>\(EZZKXML.escape(evidenceNumber))</d:ConversionRecordEvidenceNumber>"
            + "<d:TimeStamp>\(EZZKSOAPDate.string(from: timestamp))</d:TimeStamp>"
    }

    private static func personData(_ person: EZZKPerson) -> String {
        let name = person.corporateBodyFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ico = person.ico.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "<d:Data><d:PersonData>",
            "<d:CorporateBody><d:CorporateBodyFullName>\(EZZKXML.escape(name))</d:CorporateBodyFullName></d:CorporateBody>",
            "<d:ID><d:IdentifierType><d:Codelist><d:CodelistCode>4001</d:CodelistCode>",
            "<d:CodelistItem><d:ItemCode>7</d:ItemCode><d:ItemName><d:ItemName>ICO</d:ItemName><d:Language>sk</d:Language></d:ItemName></d:CodelistItem>",
            "</d:Codelist></d:IdentifierType>",
            "<d:IdentifierValue>\(EZZKXML.escape(ico))</d:IdentifierValue></d:ID>",
            "</d:PersonData></d:Data>"
        ].joined()
    }
}
