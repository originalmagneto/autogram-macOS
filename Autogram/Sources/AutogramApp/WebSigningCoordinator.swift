import Foundation
import AppKit
import AutogramKit
import AutogramWebBridge
import Observation
import os

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

    private let log = Logger(subsystem: "sk.autogram.Autogram", category: "web-signing")

    private static let timestampPreferenceKey = "webSigningAddsQualifiedTimestamp"

    /// Portals ask for Baseline B, which carries no timestamp, and the phone
    /// then offers only the handwritten-equivalent signature. Turning this on
    /// upgrades to Baseline T and adds a qualified timestamp.
    ///
    /// Off by default: slovensko.sk rejected a submission whose signature
    /// carried a timestamp it had not asked for. The portal decides what it
    /// accepts, so the safe default is to send exactly what it requested.
    var addsQualifiedTimestamp: Bool {
        didSet { UserDefaults.standard.set(addsQualifiedTimestamp, forKey: Self.timestampPreferenceKey) }
    }

    /// The level actually used, after the timestamp preference is applied.
    private func effectiveLevel(for request: WebSignRequest) -> String {
        guard addsQualifiedTimestamp, request.signatureLevel.hasSuffix("_B") else {
            return request.signatureLevel
        }
        // Only the trailing marker, never the "_B" inside "_BASELINE".
        return request.signatureLevel.dropLast(2) + "_T"
    }

    /// Shown in the sheet so the consequence of the toggle is visible before signing.
    var effectiveLevelDescription: String {
        guard let pending else { return "" }
        return effectiveLevel(for: pending.request).replacingOccurrences(of: "_", with: " ")
    }

    private var continuation: CheckedContinuation<WebSignResponse, Error>?
    private let settingsStore: AppSettingsStore
    private let signedDocumentStore: SignedDocumentStore
    let mobileSigning: MobileSigningCoordinator

    init(settingsStore: AppSettingsStore, signedDocumentStore: SignedDocumentStore) {
        let defaults = UserDefaults.standard
        self.addsQualifiedTimestamp = defaults.object(forKey: Self.timestampPreferenceKey) as? Bool ?? false
        self.settingsStore = settingsStore
        self.signedDocumentStore = signedDocumentStore
        self.mobileSigning = MobileSigningCoordinator(settingsStore: settingsStore)
    }

    /// Keeps a copy of what was signed and lists it among recent documents.
    ///
    /// The page gets its own copy over the bridge, so without this the signature
    /// would leave no trace on the Mac at all: nothing to re-check later, and
    /// nothing in the sidebar.
    @discardableResult
    private func archive(_ data: Data, for request: WebSignRequest) -> URL? {
        guard settingsStore.settings.webSigningSavesLocally else { return nil }
        let configured = settingsStore.settings.webSigningOutputPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = configured.isEmpty
            ? SigningSessionStore.outputDirectoryURL()
            : URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
        let base = (request.filename as NSString).deletingPathExtension
        let stem = (base.isEmpty ? "dokument" : base) + "_podpisane"
        let ext = request.eform == nil ? "pdf" : "asice"

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory.appendingPathComponent(stem).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) {
                let stamp = Self.fileStampFormatter.string(from: Date())
                url = directory.appendingPathComponent("\(stem)-\(stamp)").appendingPathExtension(ext)
            }
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            // A failed archive must not fail the signature: the page already has
            // a valid signed document either way.
            log.error("Web signature archive failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Whether signing with a phone is offered for this request.
    var mobileSigningAvailable: Bool { settingsStore.settings.mobileSigningEnabled }

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
        // Activating the app is not enough when it has no key window: the sheet
        // then opens behind whatever the person was looking at.
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !$0.isMiniaturized }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.requestUserAttention(.criticalRequest)
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

    /// Signs with the eID over NFC on a phone through the Autogram v mobile
    /// relay. Needs no card reader and no PIN here: the phone collects both.
    /// The relay accepts the same eForm attributes as the local engine, so a
    /// state-portal form works on this path too.
    func confirmViaMobile() async {
        guard let pending else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        do {
            let bytes = try Self.decode(pending.request)
            let isEForm = pending.request.eform != nil
            let requested = effectiveLevel(for: pending.request)
            let wantsTimestamp = requested.hasSuffix("_T")
            let level: AVMSignatureLevel = isEForm || requested.hasPrefix("XAdES")
                ? (wantsTimestamp ? .xadesT : .xadesB)
                : (wantsTimestamp ? .padesT : .padesB)

            let upload = AVMUploadRequest(
                filename: pending.request.filename,
                data: bytes,
                mimeType: isEForm ? AVMUploadRequest.xmlMimeType : AVMUploadRequest.pdfMimeType,
                level: level,
                container: isEForm ? .asicE : nil,
                eform: pending.request.eform)

            let document = try await mobileSigning.sign(upload)
            guard let content = document.data else {
                throw Failure.malformedPayload
            }
            let signers = document.signers ?? []
            let saved = archive(content, for: pending.request)
            signedDocumentStore.record(displayName: pending.request.filename,
                                       origin: .browser,
                                       method: .mobile,
                                       signatureLevel: requested,
                                       signedBy: AVMResultMapper.signatureLabel(signers: signers),
                                       url: saved)
            finish(.success(WebSignResponse(
                requestID: pending.request.requestID,
                content: content.base64EncodedString(),
                signedBy: AVMResultMapper.signatureLabel(signers: signers),
                issuedBy: signers.first?.issuedBy ?? "")))
        } catch is CancellationError {
            errorText = "Podpisovanie mobilom ste zrušili."
        } catch {
            errorText = error.localizedDescription
        }
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
            let level = effectiveLevel(for: pending.request)
            let wantsTimestamp = level.hasSuffix("_T")
            let signingRequest = SigningRequest(
                pdfData: bytes,
                identityID: identityID,
                includeTimestamp: wantsTimestamp,
                tsaURL: wantsTimestamp ? settingsStore.settings.activeTSA.url : nil,
                outputFormat: pending.request.eform == nil ? .embeddedPAdES : .attachedASIC,
                pin: pin.isEmpty ? nil : pin,
                eform: pending.request.eform,
                signatureLevelOverride: level,
                filename: pending.request.filename)

            let signed = try await provider.sign(signingRequest)
            let payload = pending.request.eform == nil ? signed.pdfData : (signed.asicData ?? signed.pdfData)
            let saved = archive(payload, for: pending.request)
            signedDocumentStore.record(displayName: pending.request.filename,
                                       origin: .browser,
                                       method: .card,
                                       signatureLevel: level,
                                       signedBy: signed.signatureLabel,
                                       url: saved)
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
        guard let data = Data(base64Encoded: request.content) ?? request.content.data(using: .utf8) else {
            throw Failure.malformedPayload
        }
        return data
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
