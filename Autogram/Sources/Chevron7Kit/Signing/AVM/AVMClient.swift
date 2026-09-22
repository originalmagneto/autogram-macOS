import Foundation

public protocol AVMHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionAVMTransport: AVMHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        guard let http = response as? HTTPURLResponse else { throw AVMError.invalidResponse }
        return (data, http)
    }
}

/// Client for the Autogram v mobile relay server (`avm-server`).
public struct AVMClient: Sendable {
    public static let publicBaseURL = URL(string: "https://autogram.slovensko.digital/api/v1")!

    public let baseURL: URL
    private let transport: any AVMHTTPTransport

    public init(baseURL: URL = AVMClient.publicBaseURL,
                transport: any AVMHTTPTransport = URLSessionAVMTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    private struct UploadResponse: Decodable {
        var guid: String
    }

    public func upload(_ request: AVMUploadRequest, key: AVMDocumentKey) async throws -> AVMDocumentReference {
        var http = URLRequest(url: baseURL.appendingPathComponent("documents"))
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        http.setValue(key.base64, forHTTPHeaderField: "X-Encryption-Key")
        http.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await send(http)
        guard response.statusCode == 200 else { throw Self.serverError(status: response.statusCode, body: data) }
        let decoded: UploadResponse
        do {
            decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        } catch {
            throw AVMError.invalidResponse
        }
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified") ?? Self.httpDate(Date())
        return AVMDocumentReference(guid: decoded.guid, key: key, lastModified: lastModified)
    }

    public func fetchSigned(_ reference: AVMDocumentReference) async throws -> AVMPollResult {
        var http = URLRequest(url: baseURL.appendingPathComponent("documents/\(reference.guid)"))
        http.httpMethod = "GET"
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        http.setValue(reference.key.base64, forHTTPHeaderField: "X-Encryption-Key")
        http.setValue(reference.lastModified, forHTTPHeaderField: "If-Modified-Since")
        http.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await send(http)
        switch response.statusCode {
        case 304:
            return .pending
        case 200:
            do {
                return .signed(try JSONDecoder().decode(AVMSignedDocument.self, from: data))
            } catch {
                throw AVMError.invalidResponse
            }
        default:
            throw Self.serverError(status: response.statusCode, body: data)
        }
    }

    public func delete(_ reference: AVMDocumentReference) async throws {
        var http = URLRequest(url: baseURL.appendingPathComponent("documents/\(reference.guid)"))
        http.httpMethod = "DELETE"
        http.setValue(reference.key.base64, forHTTPHeaderField: "X-Encryption-Key")
        let (data, response) = try await send(http)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 404 else {
            throw Self.serverError(status: response.statusCode, body: data)
        }
    }

    /// Link encoded into the QR code. The AVM app accepts only the public host.
    public func qrCodeURL(for reference: AVMDocumentReference) -> URL {
        let raw = baseURL.absoluteString
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return URL(string: "\(base)/qr-code?guid=\(reference.guid)&key=\(reference.key.queryValue)")!
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as AVMError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AVMError.transport(error.localizedDescription)
        }
    }

    static func serverError(status: Int, body: Data) -> AVMError {
        let parsed = try? JSONDecoder().decode(AVMServerErrorBody.self, from: body)
        return .server(status: status, code: parsed?.code, message: parsed?.message)
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}
