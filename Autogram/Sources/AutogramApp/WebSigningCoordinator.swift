import Foundation
import AppKit
import AutogramKit
import AutogramWebBridge
import Observation

/// Drives one signing request that arrived from a state portal through the
/// browser extension.
///
/// A page may not sign silently, so every request raises the app and waits for
/// the person to pick a certificate and enter the PIN. Requests are handled one
/// at a time: a second one while the first is open is refused rather than
/// queued, which keeps it obvious which document a PIN belongs to.
@Observable
@MainActor
final class WebSigningCoordinator {
    struct Pending: Identifiable {
        let id: String
        let request: WebSignRequest
        let sizeDescription: String
        let kindDescription: String
    }

    enum Failure: LocalizedError {
        case busy
        case cancelled
        case tooLarge(Int)
        case malformedPayload
        case identityUnavailable

        var errorDescription: String? {
            switch self {
            case .busy:
                return "Autogram už spracúva inú požiadavku na podpis."
            case .cancelled:
                return "Podpisovanie ste zrušili."
            case .tooLarge(let bytes):
                let megabytes = Double(bytes) / 1_048_576
                return String(format: "Dokument má %.1f MB, čo je nad limitom pre podpis z prehliadača.", megabytes)
            case .malformedPayload:
                return "Obsah dokumentu sa nepodarilo prečítať."
            case .identityUnavailable:
                return "Nie je vybraný certifikát na podpisovanie."
            }
        }
    }

    private(set) var pending: Pending?
    var pin: String = ""
    var selectedIdentityID: String?
    var identities: [SigningIdentityInfo] = []
    private(set) var isWorking = false
    private(set) var errorText: String?

    private var continuation: CheckedContinuation<WebSignResponse, Error>?
    private let settingsStore: AppSettingsStore

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    private var provider: any QualifiedSigningProviding { settingsStore.signingProvider }

    /// Called from the XPC bridge. Suspends until the person signs or cancels.
    func handle(_ request: WebSignRequest) async throws -> WebSignResponse {
        guard pending == nil else { throw Failure.busy }

        let bytes = try Self.decode(request)
        guard bytes.count <= WebSigningBridge.maximumPayloadBytes else {
            throw Failure.tooLarge(bytes.count)
        }

        pending = Pending(id: request.requestID,
                          request: request,
                          sizeDescription: Self.describeSize(bytes.count),
                          kindDescription: Self.describeKind(request))
        pin = ""
        errorText = nil
        NSApp.activate(ignoringOtherApps: true)
        await refreshIdentities()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func refreshIdentities() async {
        let discovered = await provider.availableIdentities()
        identities = discovered
        if selectedIdentityID == nil || !discovered.contains(where: { $0.id == selectedIdentityID }) {
            selectedIdentityID = discovered.first?.id
        }
    }

    func cancel() {
        finish(.failure(Failure.cancelled))
    }

    func confirm() async {
        guard let pending, let identityID = selectedIdentityID else {
            errorText = Failure.identityUnavailable.errorDescription
            return
        }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let bytes = try Self.decode(pending.request)
            let signingRequest = SigningRequest(
                pdfData: bytes,
                identityID: identityID,
                includeTimestamp: pending.request.signatureLevel.hasSuffix("_T"),
                tsaURL: pending.request.signatureLevel.hasSuffix("_T") ? settingsStore.settings.activeTSA.url : nil,
                outputFormat: pending.request.eform == nil ? .embeddedPAdES : .attachedASIC,
                pin: pin.isEmpty ? nil : pin,
                eform: pending.request.eform,
                signatureLevelOverride: pending.request.signatureLevel,
                filename: pending.request.filename)

            let signed = try await provider.sign(signingRequest)
            let payload = pending.request.eform == nil ? signed.pdfData : (signed.asicData ?? signed.pdfData)
            finish(.success(WebSignResponse(
                requestID: pending.request.requestID,
                content: payload.base64EncodedString(),
                signedBy: signed.signatureLabel,
                issuedBy: identities.first(where: { $0.id == identityID })?.issuerSummary ?? "")))
        } catch {
            // Kept open so a mistyped PIN can be corrected without the page
            // having to start over.
            errorText = error.localizedDescription
        }
    }

    private func finish(_ result: Result<WebSignResponse, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        pending = nil
        pin = ""
        continuation.resume(with: result)
    }

    private static func decode(_ request: WebSignRequest) throws -> Data {
        switch request.payload {
        case .inline(let text):
            guard let data = Data(base64Encoded: text) ?? text.data(using: .utf8) else {
                throw Failure.malformedPayload
            }
            return data
        }
    }

    private static func describeSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func describeKind(_ request: WebSignRequest) -> String {
        if request.eform != nil { return "Elektronický formulár (XML Data Container)" }
        if request.payloadMimeType.contains("pdf") { return "Dokument PDF" }
        return request.payloadMimeType
    }
}
