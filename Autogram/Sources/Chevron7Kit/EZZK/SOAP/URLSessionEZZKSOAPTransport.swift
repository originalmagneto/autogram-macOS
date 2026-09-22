import CryptoKit
import Foundation
import Security

public enum EZZKCertificatePin {
    public static func sha256Hex(of der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    public static func matches(leafCertificateDER der: Data, expectedSHA256Hex: String) -> Bool {
        let expected = expectedSHA256Hex.lowercased().replacingOccurrences(of: ":", with: "")
        return sha256Hex(of: der) == expected
    }
}

/// SOAP transport for one EZZK environment: ephemeral, no cookie storage (the token
/// cookie is set by hand), no redirects, and on test only the pinned certificate.
public struct URLSessionEZZKSOAPTransport: EZZKHTTPTransport, Sendable {
    private let session: URLSession
    private let pinnedSHA256: String?

    public init(environment: EZZKEnvironment) {
        self.init(pinnedSHA256: environment.pinnedCertificateSHA256, configuration: .ephemeral)
    }

    init(pinnedSHA256: String?, configuration: URLSessionConfiguration) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.pinnedSHA256 = pinnedSHA256
        self.session = URLSession(configuration: configuration,
                                  delegate: EZZKSOAPSessionDelegate(pinnedSHA256: pinnedSHA256),
                                  delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw EZZKError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as URLError where error.code == .cancelled || error.code == .serverCertificateUntrusted {
            // The delegate cancels the challenge when the served certificate is not the pinned
            // one, which URLSession reports as either code here. But the same `.cancelled` code
            // also surfaces when the surrounding Swift task was cancelled (URLSession cancels the
            // underlying task cooperatively), and that must never be misreported as a changed
            // certificate: check `Task.isCancelled` first and prefer plain cancellation.
            if Task.isCancelled {
                throw CancellationError()
            }
            guard pinnedSHA256 != nil else {
                throw error
            }
            throw EZZKError.untrustedCertificate
        }
    }
}

final class EZZKSOAPSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let pinnedSHA256: String?

    init(pinnedSHA256: String?) {
        self.pinnedSHA256 = pinnedSHA256
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        // The password travels in the body and the token in a cookie; neither may leave the host.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let pinnedSHA256 else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              EZZKCertificatePin.matches(leafCertificateDER: SecCertificateCopyData(leaf) as Data,
                                         expectedSHA256Hex: pinnedSHA256) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
