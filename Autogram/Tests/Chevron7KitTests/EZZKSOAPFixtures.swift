// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
@testable import Chevron7Kit

enum EZZKSOAPFixtures {
    static let envelopeOpen = #"<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing">"#

    static func loginSucceeded(token: String = "token-1", account: String = "ucet-test") -> String {
        envelopeOpen
            + #"<s:Header><a:Action s:mustUnderstand="1">http://ditec/2017/06/iam/core/ILogInService/LogInResponse</a:Action></s:Header><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content i:type="TokenLogInOutput" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode i:nil="true"/><ApplicationName>Centrálna evidencia EZZK</ApplicationName><AuthenticationType>L</AuthenticationType><Account><Id>ad81ed76-4406-407f-a5ed-6101fb638914</Id><Name>"#
            + account
            + #"</Name></Account><AuthenticationData i:nil="true"/><IdentityDescriptor></IdentityDescriptor><Negative>false</Negative><Subject i:nil="true"/><TokenDescriptor>"#
            + token
            + #"</TokenDescriptor><ReturnUrl i:nil="true"/></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#
    }

    static func loginRejected(code: String = "CORE-003") -> String {
        envelopeOpen
            + #"<s:Header><a:Action s:mustUnderstand="1">http://ditec/2017/06/iam/core/ILogInService/LogInResponse</a:Action></s:Header><s:Body><OutputMessageOf_LogInOutput xmlns="http://ditec/2017/06/iam/core"><Content i:type="TokenLogInOutput" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><ErrorCode>"#
            + code
            + #"</ErrorCode><ApplicationName>Centrálna evidencia EZZK</ApplicationName><AuthenticationType>L</AuthenticationType><Account i:nil="true"/><AuthenticationData i:nil="true"/><IdentityDescriptor i:nil="true"/><Negative>true</Negative><Subject i:nil="true"/><TokenDescriptor i:nil="true"/><ReturnUrl i:nil="true"/></Content></OutputMessageOf_LogInOutput></s:Body></s:Envelope>"#
    }

    static func evidenceNumbers(_ numbers: [String]) -> String {
        let list = numbers.map {
            "<b:ConversionRecordEvidenceNumberList><b:ConversionRecordEvidenceNumber>\($0)</b:ConversionRecordEvidenceNumber></b:ConversionRecordEvidenceNumberList>"
        }.joined()
        return envelopeOpen
            + #"<s:Header><a:Action s:mustUnderstand="1">http://www.ditec.sk/IEZZKService/IEZZKService/GetConversionRecordEvidenceNumberResponse</a:Action></s:Header><s:Body><GetConversionRecordEvidenceNumberResponse xmlns="http://www.ditec.sk/IEZZKService"><GetConversionRecordEvidenceNumberResult xmlns:b="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.PoskytnutieEvidencnehoCislaWS" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><Container xmlns="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><MessageId>cf4712c4-cd58-4562-8113-ce25b44a2718</MessageId><RecipientBusinessReference i:nil="true"/><RecipientId i:nil="true"/><Result><Code>0</Code><Description>OK</Description><ProcessingInfo>1</ProcessingInfo><Object><Class>FORM</Class><Encoding>XML</Encoding><Id>ff273f2c-cb8d-468a-bb97-2c455a75a84c</Id><IsSigned>false</IsSigned><Mimetype>application/xml</Mimetype><Data>"#
            + list
            + #"</Data></Object></Result></Container></GetConversionRecordEvidenceNumberResult></GetConversionRecordEvidenceNumberResponse></s:Body></s:Envelope>"#
    }

    /// Reply with a result and no data, as consume, receive and a 101 rejection send it.
    static func result(code: Int, description: String, operation: String = "ConsumeConversionRecordEvidenceNumber") -> String {
        envelopeOpen
            + #"<s:Header><a:Action s:mustUnderstand="1">http://www.ditec.sk/IEZZKService/IEZZKService/"#
            + operation
            + #"Response</a:Action></s:Header><s:Body><"#
            + operation
            + #"Response xmlns="http://www.ditec.sk/IEZZKService"><"#
            + operation
            + #"Result xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><Container xmlns="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><MessageId>736609ff-a5c3-431d-aea2-9947f51246ff</MessageId><RecipientBusinessReference i:nil="true"/><RecipientId i:nil="true"/><Result><Code>"#
            + String(code)
            + "</Code><Description>" + description + "</Description>"
            + #"<ProcessingInfo>3</ProcessingInfo><Object><Class>FORM</Class><Encoding>XML</Encoding><Id>d285b130-05ab-48f7-b69a-41f32342f418</Id><IsSigned>false</IsSigned><Mimetype>application/xml</Mimetype><Data i:nil="true"/></Object></Result></Container></"#
            + operation + "Result></" + operation + "Response></s:Body></s:Envelope>"
    }

    static let unauthorized = result(code: 101, description: "Nemáte oprávnenie na volanie služby",
                                     operation: "GetConversionRecordEvidenceNumber")

    static func fault(subcode: String, reason: String) -> String {
        envelopeOpen
            + #"<s:Header><a:Action s:mustUnderstand="1">http://schemas.microsoft.com/net/2005/12/windowscommunicationfoundation/dispatcher/fault</a:Action></s:Header><s:Body><s:Fault><s:Code><s:Value>s:Receiver</s:Value><s:Subcode><s:Value xmlns:a="http://schemas.microsoft.com/net/2005/12/windowscommunicationfoundation/dispatcher">a:"#
            + subcode
            + #"</s:Value></s:Subcode></s:Code><s:Reason><s:Text xml:lang="en-US">"#
            + reason
            + #"</s:Text></s:Reason></s:Fault></s:Body></s:Envelope>"#
    }

    static let serviceNotInitialized = fault(
        subcode: "InternalServiceFault",
        reason: "The service implementation object was not initialized or is not available.")

    static let deserializationFailed = fault(
        subcode: "DeserializationFailed",
        reason: "The formatter threw an exception while trying to deserialize the message.")

    static func publicRecordFound(code: Int = 0) -> String {
        envelopeOpen
            + #"<s:Header><a:Action s:mustUnderstand="1">http://www.ditec.sk/IEZZKService/IEZZKService/GetConversionRecordInformationPurposeResponse</a:Action></s:Header><s:Body><GetConversionRecordInformationPurposeResponse xmlns="http://www.ditec.sk/IEZZKService"><GetConversionRecordInformationPurposeResult xmlns:b="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.PoskytnutieZaznamuPreInformativneUcelyWS" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:Container><b:MessageId>e536779f-7d4b-45f9-bd89-b823e9c2d2d5</b:MessageId><b:RecipientBusinessReference i:nil="true"/><b:RecipientId i:nil="true"/><b:Result xmlns:c="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><c:Code>"#
            + String(code)
            + #"</c:Code><c:Description>OK</c:Description><c:ProcessingInfo>1</c:ProcessingInfo><c:Object><c:Class>FORM</c:Class><c:Encoding>XML</c:Encoding><c:Id>528061ce-d8a5-4ec8-a89c-1f945fdce9bf</c:Id><c:IsSigned>false</c:IsSigned><c:Mimetype>application/xml</c:Mimetype><c:Data><c:ConversionExecutionDateTime>2026-08-24T18:35:44+02:00</c:ConversionExecutionDateTime><c:ConversionRecordEvidenceNumber>1563-260824-1</c:ConversionRecordEvidenceNumber><c:NewDocumentFormat>PDF/A-2</c:NewDocumentFormat><c:NewDocumentName>Dokument A.pdf</c:NewDocumentName><c:NewDocumentNumberOfSheets i:nil="true"/><c:OriginalDocumentFormat/><c:OriginalDocumentName>Dokument A</c:OriginalDocumentName><c:OriginalDocumentNumberOfSheets>1</c:OriginalDocumentNumberOfSheets><c:PersonPerformingConversion>Advokátska kancelária Test</c:PersonPerformingConversion><c:Purpose>0</c:Purpose><c:ReceiptDate>2026-08-24T16:37:43Z</c:ReceiptDate></c:Data></c:Object></b:Result></b:Container></GetConversionRecordInformationPurposeResult></GetConversionRecordInformationPurposeResponse></s:Body></s:Envelope>"#
    }

    static let publicRecordNotFound = envelopeOpen
        + #"<s:Header><a:Action s:mustUnderstand="1">http://www.ditec.sk/IEZZKService/IEZZKService/GetConversionRecordInformationPurposeResponse</a:Action></s:Header><s:Body><GetConversionRecordInformationPurposeResponse xmlns="http://www.ditec.sk/IEZZKService"><GetConversionRecordInformationPurposeResult xmlns:b="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.PoskytnutieZaznamuPreInformativneUcelyWS" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><b:Container><b:MessageId>bb3ba455-a176-48ed-b7a4-2f44a18850c7</b:MessageId><b:RecipientBusinessReference i:nil="true"/><b:RecipientId i:nil="true"/><b:Result xmlns:c="http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"><c:Code>105</c:Code><c:Description>Evidenčné číslo záznamu o zaručenej konverzii nie je evidované</c:Description><c:ProcessingInfo>3</c:ProcessingInfo><c:Object><c:Class>FORM</c:Class><c:Encoding>XML</c:Encoding><c:Id>64b0effa-5676-4c16-809d-7b699a1d0a7a</c:Id><c:IsSigned>false</c:IsSigned><c:Mimetype>application/xml</c:Mimetype><c:Data i:nil="true"/></c:Object></b:Result></b:Container></GetConversionRecordInformationPurposeResult></GetConversionRecordInformationPurposeResponse></s:Body></s:Envelope>"#

    static let options = envelopeOpen
        + #"<s:Header><a:Action s:mustUnderstand="1">http://www.ditec.sk/IEZZKService/IEZZKService/GetOptionsResponse</a:Action></s:Header><s:Body><GetOptionsResponse xmlns="http://www.ditec.sk/IEZZKService"/></s:Body></s:Envelope>"#

    static func document(_ xml: String) throws -> XMLDocument {
        try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
    }
}

/// Replays scripted HTTP replies and records every request.
final class SOAPScriptedTransport: EZZKHTTPTransport, @unchecked Sendable {
    enum Step {
        case reply(status: Int, body: String, headers: [String: String])
        case fail(Error)

        static func ok(_ body: String, headers: [String: String] = [:]) -> Step {
            .reply(status: 200, body: body, headers: headers)
        }
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var recorded: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    /// SOAP operation of each recorded request, read from the Content-Type action.
    var operations: [String] {
        requests.compactMap { request in
            request.value(forHTTPHeaderField: "Content-Type")?
                .components(separatedBy: "/").last?
                .replacingOccurrences(of: "\"", with: "")
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let step: Step = lock.withLock {
            recorded.append(request)
            return steps.isEmpty ? .fail(URLError(.badServerResponse)) : steps.removeFirst()
        }
        switch step {
        case let .reply(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            return (Data(body.utf8), response)
        case let .fail(error):
            throw error
        }
    }
}
