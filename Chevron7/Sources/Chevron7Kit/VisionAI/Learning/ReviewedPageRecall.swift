// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Brings back the reviewer's own boxes when the same document (same SHA-256)
/// is opened again. A page with a complete review in the example bank shows
/// that review instead of fresh detection; every recalled box is a pending
/// suggestion, because each conversion needs its own human review.
public enum ReviewedPageRecall {
    /// Audit value stored in `SecurityElement.detectionSource` for a recalled box.
    public static let detectionSource = "reviewedPage"

    public static func apply(to detected: [SecurityElement], documentSHA256: String,
                             reviewedPages: [ReviewedBankPage]) -> [SecurityElement] {
        let pages = reviewedPages.filter { $0.documentSHA256 == documentSHA256 }
        guard !pages.isEmpty else { return detected }
        let reviewedIndices = Set(pages.map(\.pageIndex))
        var result = detected.filter { !reviewedIndices.contains($0.pageIndex) }
        for page in pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            for box in page.boxes {
                result.append(SecurityElement(kind: box.kind, pageIndex: page.pageIndex, boundingBox: box.box,
                                              confidence: 1, detectedByAI: true, reviewState: .pending,
                                              detectionSource: detectionSource))
            }
        }
        return result
    }
}
