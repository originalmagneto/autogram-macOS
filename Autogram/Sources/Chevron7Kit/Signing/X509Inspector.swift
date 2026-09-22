import Foundation
import Security

public enum X509Inspector {
    public struct CertificateFacts: Sendable, Equatable {
        public var serialNumberDecimal: String
        public var issuerRFC2253: String
        public var subjectRFC2253: String
    }

    public static func facts(certificateData: Data) -> CertificateFacts? {
        let bytes = [UInt8](certificateData)
        guard let cert = DERNode.firstTLV(bytes: bytes, at: 0), cert.tag == 0x30,
              let tbs = DERNode.children(bytes: bytes, in: cert.contentRange).first,
              tbs.tag == 0x30 else { return nil }

        var serialBytes: [UInt8] = []
        var issuerName: String = ""
        var subjectName: String = ""
        var seenSerial = false

        for node in DERNode.children(bytes: bytes, in: tbs.contentRange) {
            if !seenSerial {
                if node.tag == 0x02 {
                    serialBytes = Array(bytes[node.contentRange])
                    seenSerial = true
                }
                continue
            }
            guard node.tag == 0x30, Self.isNameNode(bytes: bytes, node: node) else { continue }
            if issuerName.isEmpty {
                issuerName = nameRFC2253(bytes: bytes, nameNode: node)
            } else {
                subjectName = nameRFC2253(bytes: bytes, nameNode: node)
                break
            }
        }
        guard seenSerial else { return nil }
        return CertificateFacts(serialNumberDecimal: decimalString(fromBytes: serialBytes),
                                issuerRFC2253: issuerName,
                                subjectRFC2253: subjectName)
    }

    public static func issuerAndSerial(certificateData: Data)
        -> (issuerDER: Data, serialRaw: [UInt8])? {
        let bytes = [UInt8](certificateData)
        guard let cert = DERNode.firstTLV(bytes: bytes, at: 0), cert.tag == 0x30,
              let tbs = DERNode.children(bytes: bytes, in: cert.contentRange).first,
              tbs.tag == 0x30 else { return nil }
        var serialRaw: [UInt8] = []
        var issuerDER: Data?
        var seenSerial = false
        for node in DERNode.children(bytes: bytes, in: tbs.contentRange) {
            if !seenSerial {
                if node.tag == 0x02 {
                    serialRaw = Array(bytes[node.contentRange])
                    seenSerial = true
                }
                continue
            }
            guard node.tag == 0x30, Self.isNameNode(bytes: bytes, node: node) else { continue }
            let full = node.fullRange
            issuerDER = Data(bytes[full])
            break
        }
        guard seenSerial, let issuer = issuerDER else { return nil }
        return (issuer, serialRaw)
    }

    static func decimalString(fromBytes raw: [UInt8]) -> String {
        var working = raw
        while working.count > 1 && working.first == 0 { working.removeFirst() }
        if working.allSatisfy({ $0 == 0 }) { return "0" }
        var digits: [Character] = []
        while !(working.count == 1 && working[0] == 0) {
            var remainder = 0
            var quotient: [UInt8] = []
            for byte in working {
                let current = remainder * 256 + Int(byte)
                quotient.append(UInt8(current / 10))
                remainder = current % 10
            }
            while quotient.count > 1 && quotient.first == 0 { quotient.removeFirst() }
            digits.append(Character(UnicodeScalar(UInt8(48 + remainder))))
            working = quotient
        }
        return String(digits.reversed())
    }

    static func isNameNode(bytes: [UInt8], node: DERNode) -> Bool {
        let children = DERNode.children(bytes: bytes, in: node.contentRange)
        return !children.isEmpty && children.allSatisfy { $0.tag == 0x31 }
    }

    static func nameRFC2253(bytes: [UInt8], nameNode: DERNode) -> String {
        let rdns = DERNode.children(bytes: bytes, in: nameNode.contentRange)
        var parts: [String] = []
        for rdn in rdns.reversed() where rdn.tag == 0x31 {
            let atvs = DERNode.children(bytes: bytes, in: rdn.contentRange).compactMap { atv -> String? in
                guard atv.tag == 0x30 else { return nil }
                let pair = DERNode.children(bytes: bytes, in: atv.contentRange)
                guard pair.count >= 2, pair[0].tag == 0x06 else { return nil }
                let typeOID = pair[0].oidString(bytes: bytes)
                if let stringValue = decodeDirectoryString(bytes: bytes, node: pair[1]) {
                    return "\(attributeTypeName(typeOID))=\(escape2253(stringValue))"
                }
                let hex = bytes[pair[1].contentRange].map { String(format: "%02X", $0) }.joined()
                return "\(attributeTypeName(typeOID))=#\(hex)"
            }
            if !atvs.isEmpty { parts.append(atvs.joined(separator: "+")) }
        }
        return parts.joined(separator: ",")
    }

    static func decodeDirectoryString(bytes: [UInt8], node: DERNode) -> String? {
        switch node.tag {
        case 0x0C, 0x13, 0x16, 0x14:
            let slice = bytes[node.contentRange]
            let text = String(decoding: slice, as: UTF8.self)
            return text
        case 0x1E:
            let slice = Array(bytes[node.contentRange].dropFirst())
            var codeUnits: [UInt16] = []
            var index = 0
            while index + 1 < slice.count {
                codeUnits.append(UInt16(slice[index]) << 8 | UInt16(slice[index + 1]))
                index += 2
            }
            return String(utf16CodeUnits: codeUnits, count: codeUnits.count)
        default:
            return nil
        }
    }

    static func attributeTypeName(_ oid: String) -> String {
        switch oid {
        case "2.5.4.3": return "CN"
        case "2.5.4.6": return "C"
        case "2.5.4.7": return "L"
        case "2.5.4.8": return "ST"
        case "2.5.4.10": return "O"
        case "2.5.4.11": return "OU"
        case "2.5.4.5": return "serialNumber"
        case "2.5.4.12": return "title"
        case "2.5.4.42": return "GN"
        case "2.5.4.4": return "SN"
        case "2.5.4.46": return "dnQualifier"
        case "2.5.4.65": return "pseudonym"
        case "1.2.840.113549.1.9.1": return "emailAddress"
        case "0.9.2342.19200300.100.1.25": return "DC"
        default: return oid
        }
    }

    static func escape2253(_ value: String) -> String {
        var out = ""
        for (index, char) in value.enumerated() {
            if ",+\"\\<>;=".contains(char) {
                out.append("\\")
                out.append(char)
            } else if index == 0 && char == "#" {
                out.append("\\#")
            } else if index == 0 && char == " " {
                out.append("\\ ")
            } else if index == value.count - 1 && char == " " {
                out.append("\\ ")
            } else {
                out.append(char)
            }
        }
        return out
    }
}
