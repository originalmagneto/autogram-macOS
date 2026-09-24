// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Decides from the file's own bytes whether signing must leave them untouched.
///
/// Adding a signature to a document that already carries one works only on the
/// original bytes: a PDFKit rewrite (visual stamp baked into the page, PDF/A
/// conversion) drops every embedded PAdES signature, and an ASiC-E re-signed from
/// its extracted PDF loses the container's signatures. The check reads bytes only,
/// so it holds with every signing provider, the demo one included.
public enum ExistingSignatureGuard {
    public enum Source: Equatable, Sendable {
        /// A PDF without an embedded signature: rewriting it is allowed.
        case unsignedPDF
        /// A PDF with at least one embedded signature: sign its bytes as they are.
        case signedPDF
        /// An ASiC container: a further signature goes into the container itself.
        case asicContainer
    }

    public static func classify(fileName: String, data: Data) -> Source {
        if isASiCContainer(fileName: fileName, data: data) { return .asicContainer }
        return pdfContainsSignature(data) ? .signedPDF : .unsignedPDF
    }

    /// Every PDF signature dictionary carries a `/ByteRange`, written outside object
    /// streams because its offsets are patched after the file is laid out.
    public static func pdfContainsSignature(_ data: Data) -> Bool {
        data.range(of: Data("/ByteRange".utf8)) != nil
    }

    public static func isASiCContainer(fileName: String, data: Data) -> Bool {
        hasContainerExtension(fileName) && data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    /// The extensions the engine treats as an ASiC container.
    public static func hasContainerExtension(_ fileName: String) -> Bool {
        ["asice", "sce", "asics", "scs"].contains((fileName as NSString).pathExtension.lowercased())
    }
}
