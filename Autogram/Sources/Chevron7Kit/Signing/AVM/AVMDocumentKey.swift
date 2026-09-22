import Foundation
import CryptoKit

/// Symmetric key that encrypts one document on the AVM server.
/// The server never stores it; every call about the document must carry it.
public struct AVMDocumentKey: Sendable, Equatable {
    public enum Failure: Error, Equatable {
        case invalidLength(Int)
    }

    public static let byteCount = 32

    public let bytes: Data

    public init(bytes: Data) throws {
        guard bytes.count == Self.byteCount else {
            throw Failure.invalidLength(bytes.count)
        }
        self.bytes = bytes
    }

    public static func generate() -> AVMDocumentKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        // 256 bits is always 32 bytes, so the throwing initializer cannot fail here.
        return try! AVMDocumentKey(bytes: data)
    }

    /// Strict base64 as sent in the `X-Encryption-Key` header.
    public var base64: String {
        bytes.base64EncodedString()
    }

    /// Base64 percent-encoded for the `key` query parameter of the QR link.
    public var queryValue: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return base64.addingPercentEncoding(withAllowedCharacters: allowed) ?? base64
    }
}
