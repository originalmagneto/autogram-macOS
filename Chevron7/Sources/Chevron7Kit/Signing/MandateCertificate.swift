// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import Security

/// Whether a certificate is a mandate certificate (MQC), the only one a guaranteed
/// conversion may be authorized with.
///
/// One rule for every scanner: the engine after the PIN, CryptoTokenKit before it and
/// the PKCS#11 bridge. A SAK card from I.CA names its MQC "<name> OPRÁVNENIE <number>";
/// other issuers say "mandát". A qualified signature certificate without that token is
/// not an MQC, however qualified its issuer is.
public enum MandateCertificate {
    public static func matches(subject: String, issuer: String = "") -> Bool {
        let text = "\(subject) \(issuer)".lowercased()
        // A commercial certificate never carries a mandate.
        if text.contains("public ca") { return false }
        return ["oprávnenie", "opravnenie", "mandát", "mandat"].contains { text.contains($0) }
    }

    /// What the reader holds, as far as the mandate goes.
    public enum CardState: Equatable, Sendable {
        /// No card that macOS reads without a PIN (none inserted, or one without a
        /// CryptoTokenKit driver, such as the eID).
        case noCard
        case mandate(label: String)
        case noMandate(labels: [String])
    }

    public static func cardState(subjects: [(subject: String, issuer: String)]) -> CardState {
        guard !subjects.isEmpty else { return .noCard }
        if let mandate = subjects.first(where: { matches(subject: $0.subject, issuer: $0.issuer) }) {
            return .mandate(label: mandate.subject)
        }
        return .noMandate(labels: subjects.map(\.subject))
    }

    /// Reads the certificates of every connected CryptoTokenKit token. Certificates
    /// are public objects on the card, so this never asks for a PIN.
    public static func currentCardState() -> CardState {
        var subjects: [(subject: String, issuer: String)] = []
        var seen = Set<String>()
        for tokenID in KeychainIdentityScanner.connectedTokenIDs() {
            for der in KeychainIdentityScanner.certificateDERs(tokenID: tokenID) {
                guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
                      let summary = SecCertificateCopySubjectSummary(certificate) as String?,
                      !summary.isEmpty,
                      !KeychainIdentityScanner.isJunk(summary),
                      !KeychainIdentityScanner.looksLikeRootCA(summary),
                      seen.insert(summary).inserted else { continue }
                let issuer = X509Inspector.facts(certificateData: der)?.issuerRFC2253 ?? ""
                subjects.append((summary, issuer))
            }
        }
        return cardState(subjects: subjects)
    }
}
