import Foundation

enum EZZKSOAPNamespace {
    static let soap = "http://www.w3.org/2003/05/soap-envelope"
    static let addressing = "http://www.w3.org/2005/08/addressing"
    static let instance = "http://www.w3.org/2001/XMLSchema-instance"
    static let service = "http://www.ditec.sk/IEZZKService"
    static let dol = "http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol"
    static let evidenceNumber = "http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.PoskytnutieEvidencnehoCislaWS"
    static let consume = "http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.SpotrebaEvidencnehoCislaWS"
    static let record = "http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.PoskytnutieZaznamuWS"
    static let receive = "http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol.PrijatieZaznamuWs"
    static let iamCore = "http://ditec/2017/06/iam/core"
}

enum EZZKXML {
    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}

public enum EZZKSOAPEnvelope {
    /// Wraps an operation element in a SOAP 1.2 envelope. The service rejects a message
    /// without the WS-Addressing Action, MessageID and To headers (ActionMismatch).
    public static func wrap(body: String, action: String, to url: URL, messageID: UUID) -> String {
        [
            "<soap:Envelope xmlns:soap=\"\(EZZKSOAPNamespace.soap)\" xmlns:a=\"\(EZZKSOAPNamespace.addressing)\">",
            "<soap:Header>",
            "<a:Action soap:mustUnderstand=\"1\">\(EZZKXML.escape(action))</a:Action>",
            "<a:MessageID>urn:uuid:\(messageID.uuidString.lowercased())</a:MessageID>",
            "<a:To soap:mustUnderstand=\"1\">\(EZZKXML.escape(url.absoluteString))</a:To>",
            "</soap:Header>",
            "<soap:Body>\(body)</soap:Body>",
            "</soap:Envelope>"
        ].joined()
    }
}

public enum EZZKSOAPDate {
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Accepts WCF values such as `2019-06-10T08:39:37.3150021Z` or `2026-08-24T18:35:44+02:00`.
    /// WCF writes up to seven fraction digits, more than `ISO8601DateFormatter` accepts.
    public static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(
            of: /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})?/) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let zone = match.3.map(String.init) ?? "Z"
        guard let base = formatter.date(from: String(match.1) + zone) else { return nil }
        let fraction = match.2.flatMap { Double("0" + String($0)) } ?? 0
        return base.addingTimeInterval(fraction)
    }
}
