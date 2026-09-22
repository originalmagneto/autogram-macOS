// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

extension SecurityElement {
    /// Raw values of the original five kinds are persisted in sessions and the example bank.
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case handwrittenSignature = "Vlastnoručný podpis"
        case officialStamp = "Úradná pečiatka"
        case embossedSeal = "Reliéfna slepotlač"
        case initial = "Parafa"
        case other = "Iný prvok"
        case certifiedSignature = "Úradne osvedčený podpis"
        case roundOfficialStamp = "Okrúhla pečiatka so štátnym znakom"
        case waxSeal = "Vosková alebo iná pečať"
        case bindingCord = "Trikolóra / viazacia šnúrka"
        case securityTape = "Prelepovacia páska alebo štítok"
        case permanentBinding = "Iné trvalé spojenie"
        case watermark = "Vodoznak"
        case securityPattern = "Ochranný vzor"
        case opticallyVariable = "Hologram / opticky variabilný prvok"
        case securityFoil = "Ochranná fólia alebo nálepka"
        case lamination = "Laminovanie"

        public var id: String { rawValue }
        public var label: String { self == .officialStamp ? "Odtlačok pečiatky" : rawValue }

        public enum Group: String, CaseIterable, Identifiable, Sendable {
            case signatures = "Podpisy", stamps = "Pečiatky a pečate", binding = "Spojenie listov"
            case protection = "Ochrana materiálu", other = "Ostatné"
            public var id: String { rawValue }
        }

        public var group: Group {
            switch self {
            case .handwrittenSignature, .initial, .certifiedSignature: return .signatures
            case .officialStamp, .roundOfficialStamp, .embossedSeal, .waxSeal: return .stamps
            case .bindingCord, .securityTape, .permanentBinding: return .binding
            case .watermark, .securityPattern, .opticallyVariable, .securityFoil, .lamination: return .protection
            case .other: return .other
            }
        }

        public var requiresHumanDescription: Bool { self == .other || self == .permanentBinding }

        public var sfSymbol: String {
            switch group {
            case .signatures: return "signature"
            case .stamps: return self == .embossedSeal ? "circle.dashed" : "seal"
            case .binding: return "link"
            case .protection: return "shield.lefthalf.filled"
            case .other: return "questionmark.circle"
            }
        }

        /// Human certification is not an appearance a visual model can establish.
        public var visualKind: Kind? {
            switch self {
            case .certifiedSignature: return .handwrittenSignature
            case .roundOfficialStamp: return .officialStamp
            case .permanentBinding, .other: return nil
            default: return self
            }
        }

        public var trainingLabel: String {
            switch self {
            case .officialStamp, .roundOfficialStamp: return "officialStamp"
            case .handwrittenSignature, .certifiedSignature: return "handwrittenSignature"
            case .embossedSeal: return "embossedSeal"
            case .initial: return "initial"
            case .bindingCord: return "bindingCord"
            case .securityTape: return "securityTape"
            case .waxSeal: return "waxSeal"
            case .watermark: return "watermark"
            case .securityPattern: return "securityPattern"
            case .opticallyVariable: return "opticallyVariable"
            case .securityFoil: return "securityFoil"
            case .lamination: return "lamination"
            case .permanentBinding: return "permanentBinding"
            case .other: return "other"
            }
        }

        /// Verified clause 1.3 catalogue. The conversion RECORD uses plain text instead.
        /// Broader UI kinds use the official manual-entry code, never a narrower assertion.
        public var codelist15Item: ZakoCodelistItem {
            let code: String
            switch self {
            case .handwrittenSignature: code = "vlastnoručný podpis"
            case .certifiedSignature: code = "úradne osvedčený podpis"
            case .officialStamp: code = "pečiatka"
            case .roundOfficialStamp: code = "okrúhla pečiatka so štátnym znakom"
            case .embossedSeal: code = "reliéfna pečiatka"
            case .watermark: code = "vodotlač"
            case .permanentBinding: code = "trvale spojenie dokumentu - iné"
            default: code = "iný manuálny vstup"
            }
            return ZakoCodelistItem(code: code, skName: self == .permanentBinding ? "Trvalé spojenie dokumentu - iné" : code.prefix(1).uppercased() + code.dropFirst())
        }
    }

    public var descriptionForRecord: String {
        let detail = verbalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? kind.label : "\(kind.label): \(detail)"
    }
}
