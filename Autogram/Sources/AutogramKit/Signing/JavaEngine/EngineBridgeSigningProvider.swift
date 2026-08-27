import Foundation
import PDFKit
@preconcurrency import AppKit
import os

/// Kvalifikované podpisovanie cez overený Java/DSS engine z Autogram macOS 2
/// (AutogramCLI-arm64 helper + machine protokol V1/V2) – port produkčnej cesty.
public final class EngineBridgeSigningProvider: QualifiedSigningProviding, @unchecked Sendable {
    public static let driverID = "eid"
    public static let syntheticIdentityIDPrefix = "engine:"
    public static let certificateIdentityPrefix = "engine-cert:"

    private let engine: AutogramCLIEngine
    private let renderer: VisibleSignatureRenderer
    private let cachedCertificates = OSAllocatedUnfairLock<[SigningCertificate]>(initialState: [])
    private let identityCache = OSAllocatedUnfairLock<(fingerprint: String, identities: [SigningIdentityInfo], fetchedAt: Date)?>(
        initialState: nil)
    private let identityCacheTTL: TimeInterval = 6
    private let driverProbeCache = OSAllocatedUnfairLock<(fingerprint: String, names: [String], at: Date)?>(initialState: nil)
    private let lastResolveErrorLock = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let logger = Logger(subsystem: "sk.autogram.macos", category: "EngineBridge")

    init(engine: AutogramCLIEngine = AutogramCLIEngine(),
         renderer: VisibleSignatureRenderer = VisibleSignatureRenderer()) {
        self.engine = engine
        self.renderer = renderer
    }

    // MARK: - QualifiedSigningProviding

    public func availableIdentities() async -> [SigningIdentityInfo] {
        let probe = await connectedDriversFingerprint()
        let fingerprint = probe?.fingerprint ?? ""
        if fingerprint.isEmpty {
            cachedCertificates.withLock { $0 = [] }
            identityCache.withLock { $0 = nil }
            return []
        }
        if let cached = identityCache.withLock({ $0 }),
           cached.fingerprint == fingerprint,
           Date().timeIntervalSince(cached.fetchedAt) < identityCacheTTL {
            return cached.identities
        }
        let identities = await computeIdentities(fingerprint: fingerprint, driverNames: probe?.names ?? [])
        identityCache.withLock { $0 = (fingerprint, identities, Date()) }
        return identities
    }

    /// Načíta certifikáty pred vykreslením grafického podpisu.
    public func resolveIdentities(pin: String) async -> [SigningIdentityInfo]? {
        do {
            let drivers = try await engine.drivers()
            let present = drivers.filter { $0.tokenPresent == true }
            let usable = present.isEmpty ? drivers.filter { $0.tokenPresent != false } : present
            guard let driverID = (usable.first(where: { $0.id == Self.driverID }) ?? usable.first)?.id else {
                lastResolveErrorLock.withLock { $0 = "Karta nie je dostupná — vložte ju do čítačky." }
                return []
            }
            // eID má chránenú autentizačnú cestu — prázdny PIN nechá BOK dialóg na middleware.
            // Komerčné karty (I.CA SecureStore a pod.) vyžadujú programovo zadaný PIN.
            guard !pin.isEmpty || driverID == Self.driverID else {
                lastResolveErrorLock.withLock { $0 = "Pre túto kartu zadajte PIN." }
                return nil
            }
            let discovery = try await engine.certificateDiscovery(driverID: driverID, pin: Secret(pin))
            guard !discovery.certificates.isEmpty else {
                lastResolveErrorLock.withLock { $0 = "Na karte neboli nájdené podpisové certifikáty." }
                return []
            }
            cachedCertificates.withLock { $0 = discovery.certificates }
            invalidateIdentityCache()
            lastResolveErrorLock.withLock { $0 = nil }
            return discovery.certificates.map(Self.identityInfo(from:))
        } catch {
            let message = error.localizedDescription
            let friendly: String
            if message.contains("PIN_INVALID") {
                friendly = "PIN má neplatný formát pre túto kartu — skontrolujte jeho dĺžku a počet číslic."
            } else if message.contains("PIN_INCORRECT") {
                friendly = "Nesprávny PIN — overte ho a skúste znova."
            } else if message.contains("PIN_LOCKED") {
                friendly = "PIN karty je zablokovaný — odomknite ju PUK kódom cez nástroj výrobcu karty."
            } else if message.contains("DRIVER_UNAVAILABLE") || message.contains("DRIVER_NOT_FOUND") {
                friendly = "Karta nie je dostupná — vložte ju do čítačky."
            } else {
                friendly = "Načítanie certifikátu zlyhalo: \(message)"
            }
            lastResolveErrorLock.withLock { $0 = friendly }
            logger.info("Certificate discovery failed: \(message, privacy: .public)")
            return nil
        }
    }

    public var lastResolveError: String? {
        lastResolveErrorLock.withLock { $0 }
    }

    public func invalidateIdentityCache() {
        identityCache.withLock { $0 = nil }
    }

    public func inspectSignatures(in fileURL: URL) async -> [DocumentSignatureInfo] {
        let canonical = EnginePaths.canonical(fileURL)
        guard FileManager.default.fileExists(atPath: canonical.path) else { return [] }
        do {
            let inspections = try await engine.inspect(files: [
                PDFItemDescriptor(id: "inspect", sourceURL: canonical)
            ])
            return inspections.flatMap(\.files).flatMap(\.signatures).map { signature in
                let state: DocumentSignatureInfo.State
                switch signature.validationState {
                case .valid: state = .valid
                case .invalid: state = .invalid
                case .indeterminate: state = .indeterminate
                }
                return DocumentSignatureInfo(
                    id: signature.id,
                    signerDisplayName: signature.signerDisplayName ?? "Neznámy podpisovateľ",
                    format: signature.format,
                    signingTime: signature.signingTime,
                    hasQualifiedTimestamp: signature.hasQualifiedTimestamp,
                    state: state,
                    detail: signature.validationReason ?? signature.subIndication)
            }
        } catch {
            logger.info("Inspection failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Odtlaček pripojených driverov + ich ľudské názvy (pre synthetic identitu).
    private func connectedDriversFingerprint() async -> (fingerprint: String, names: [String])? {
        if let cached = driverProbeCache.withLock({ $0 }),
           Date().timeIntervalSince(cached.at) < 2.5 {
            return cached.fingerprint.isEmpty ? nil : (cached.fingerprint, cached.names)
        }
        do {
            let drivers = try await engine.drivers()
            let present = drivers.filter { $0.tokenPresent == true }
            let usable = present.isEmpty
                ? drivers.filter { $0.tokenPresent != false }
                : present
            let fingerprint = usable.map(\.id).sorted().joined(separator: ",")
            let names = usable.sorted { $0.id < $1.id }.map(\.displayName)
            driverProbeCache.withLock { $0 = (fingerprint, names, Date()) }
            return fingerprint.isEmpty ? nil : (fingerprint, names)
        } catch {
            logger.info("Driver detection failed: \(error.localizedDescription, privacy: .public)")
            if let cached = driverProbeCache.withLock({ $0 }), !cached.fingerprint.isEmpty {
                return (cached.fingerprint, cached.names)
            }
            return nil
        }
    }

    private func computeIdentities(fingerprint: String, driverNames: [String]) async -> [SigningIdentityInfo] {
        guard !fingerprint.isEmpty else { return [] }
        let cached = cachedCertificates.withLock { $0 }
        if !cached.isEmpty {
            return cached.map(Self.identityInfo(from:))
        }
        return [Self.syntheticIdentity(driverNames: driverNames)]
    }

    public func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        guard let pin = request.pin, !pin.isEmpty else {
            throw SigningError.identityUnavailable
        }

        let drivers = (try? await engine.drivers()) ?? []
        let present = drivers.filter { $0.tokenPresent == true }
        let usable = present.isEmpty ? drivers.filter { $0.tokenPresent != false } : present
        let connectedDriver = usable.first(where: { $0.id == Self.driverID }) ?? usable.first
        guard let driverID = connectedDriver?.id else {
            cachedCertificates.withLock { $0 = [] }
            invalidateIdentityCache()
            throw SigningError.identityUnavailable
        }

        let preferredSerial = request.identityID.hasPrefix(Self.certificateIdentityPrefix)
            ? String(request.identityID.dropFirst(Self.certificateIdentityPrefix.count))
            : nil
        // eID PKCS#11: C_Login pri výpise kľúčov a znova pri podpise — dva BOK dialógy sú očakávané
        // (pôvodný Autogram aj eID klient). Neskratovať CERTIFICATES.
        statusLog("Čítam podpisové certifikáty z karty…")
        let discovery: CertificateDiscovery
        do {
            discovery = try await engine.certificateDiscovery(driverID: driverID, pin: Secret(pin))
        } catch {
            cachedCertificates.withLock { $0 = [] }
            invalidateIdentityCache()
            throw Self.mapAny(error)
        }
        guard !discovery.certificates.isEmpty else {
            cachedCertificates.withLock { $0 = [] }
            invalidateIdentityCache()
            throw SigningError.identityUnavailable
        }
        cachedCertificates.withLock { $0 = discovery.certificates }
        guard let certificate = Self.selectCertificate(from: discovery.certificates,
                                                       preferredSerialNumber: preferredSerial) else {
            throw SigningError.identityUnavailable
        }

        let workDirectory = try Self.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let wantsPAdES = request.outputFormat == .embeddedPAdES
        var sourceURL: URL
        if !wantsPAdES, !request.extraFiles.isEmpty {
            sourceURL = workDirectory.appendingPathComponent("kontajner.asice")
            try Self.packageContainer(entries: request.extraFiles)
                .write(to: sourceURL, options: [.atomic])
        } else {
            sourceURL = workDirectory.appendingPathComponent("document.pdf")
            try request.pdfData.write(to: sourceURL, options: [.atomic])
        }

        var appearanceRequest: VisibleSignatureRequest?
        if wantsPAdES, let stamp = request.visualStamp {
            statusLog("Renderujem grafický podpis…")
            appearanceRequest = try self.visibleAppearance(for: stamp,
                                                           certificateDisplayName: certificate.displayName,
                                                           qualification: certificate.certificateQualification,
                                                           pdfData: request.pdfData,
                                                           directory: workDirectory)
        }

        let signingFile = SigningFile(id: "document",
                                      sourceURL: EnginePaths.canonical(sourceURL),
                                      visibleAppearance: appearanceRequest)
        let engineRequest = EngineSigningRequest(
            sessionID: UUID(),
            driverID: driverID,
            certificateSerial: certificate.serialNumber,
            pin: Secret(pin),
            files: [signingFile],
            outputFormat: wantsPAdES ? .pades : .asiceXAdES)

        statusLog("Podpisujem kvalifikovaným podpisom (DSS)…")
        var outputURL: URL?
        do {
            for try await event in engine.sign(request: engineRequest) {
                switch event {
                case .activity(let phase):
                    statusLog("Engine: \(phase.label)")
                case .completed(_, let url):
                    outputURL = url
                case .failed(_, let failure):
                    throw failure
                case .started, .fileSigning:
                    continue
                case .cancelled:
                    throw CancellationError()
                }
            }
        } catch {
            throw Self.mapAny(error)
        }

        guard let outputURL, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw SigningError.signingFailed("Engine nevrátil podpísaný súbor.")
        }
        let signedData: Data
        do {
            signedData = try Data(contentsOf: outputURL)
        } catch {
            throw SigningError.signingFailed("Podpísaný výstup sa nepodarilo prečítať.")
        }
        guard !signedData.isEmpty else {
            throw SigningError.signingFailed("Engine nevrátil podpísaný súbor.")
        }

        if wantsPAdES {
            if appearanceRequest != nil, !Self.hasVisibleSignatureField(in: signedData) {
                throw SigningError.signingFailed(
                    "Podpis je v PDF, ale grafické pole ostalo neviditeľné (Rect 0×0). Skúste bez PDF/A alebo Reset placement.")
            }
            return SignedConversionResult(pdfData: signedData,
                                          asicData: nil,
                                          signedAt: Date(),
                                          signatureLabel: certificate.displayName,
                                          isLegallyBinding: true)
        }
        return SignedConversionResult(pdfData: request.pdfData,
                                      asicData: signedData,
                                      signedAt: Date(),
                                      signatureLabel: certificate.displayName,
                                      isLegallyBinding: true)
    }

    // MARK: - Vizuálny podpis (port VisibleSignatureRenderer + PDFCoordinateConverter)

    func visibleAppearance(for stamp: VisualStampSpec,
                           certificateDisplayName: String?,
                           qualification: String?,
                           pdfData: Data,
                           directory: URL) throws -> VisibleSignatureRequest {
        guard let document = PDFDocument(data: pdfData),
              document.pageCount > 0 else {
            throw SigningError.signingFailed("PDF sa nepodarilo otvoriť pre vizuálny podpis.")
        }
        let pageIndex = min(max(stamp.pageIndex, 0), document.pageCount - 1)
        guard let page = document.page(at: pageIndex) else {
            throw SigningError.signingFailed("Strana vizuálneho podpisu neexistuje.")
        }
        let cropBox = page.bounds(for: .cropBox)
        guard cropBox.width > 0, cropBox.height > 0 else {
            throw SigningError.signingFailed("Neplatný rozmer strany pre vizuálny podpis.")
        }

        let pageRect: CGRect
        if let explicit = stamp.pdfPageRect, explicit.width > 1, explicit.height > 1,
           cropBox.intersects(explicit) {
            pageRect = explicit.intersection(cropBox)
        } else {
            let width = max(stamp.normalizedRect.width * cropBox.width, 120)
            let height = max(stamp.normalizedRect.height * cropBox.height, 60)
            let originX = stamp.normalizedRect.x * cropBox.width
            let originY = (1 - stamp.normalizedRect.y - stamp.normalizedRect.height) * cropBox.height
            pageRect = CGRect(x: originX, y: originY, width: width, height: height)
                .intersection(cropBox)
        }
        guard pageRect.width > 8, pageRect.height > 8 else {
            throw SigningError.signingFailed("Vizuálny podpis je mimo stranu dokumentu (po PDF/A sa zmenili rozmery). Reset placement a skúste znova.")
        }
        let placement = VisibleSignaturePlacement(pageIndex: pageIndex,
                                                  pageRect: pageRect,
                                                  rotationDegrees: stamp.rotationDegrees)

        let store = SignatureAssetStore(applicationSupportRoot: directory)
        let artworkName = "artwork-\(UUID().uuidString).png"
        let asset = SignatureAsset(id: UUID(), kind: .png, managedFilename: artworkName)
        do {
            try FileManager.default.createDirectory(at: store.assetsDirectory,
                                                    withIntermediateDirectories: true)
            let artworkPNG = stamp.imagePNG.flatMap { Self.pngDataOrTextFallback(fullName: stamp.fullName, timestamp: stamp.timestamp, provided: $0) }
                ?? Self.textArtworkPNG(fullName: stamp.fullName, timestamp: stamp.timestamp)
            try artworkPNG.write(to: store.fileURL(for: asset), options: [.atomic])
        } catch {
            throw SigningError.signingFailed("Grafiku podpisu sa nepodarilo pripraviť.")
        }

        let content = VisibleSignatureCardContent(
            signerName: certificateDisplayName ?? stamp.fullName,
            certificateQualification: qualification ?? stamp.qualification ?? "Kvalifikovaný elektronický podpis")
        let signingTime = Date()
        let renderedURL: URL
        do {
            renderedURL = try VisibleSignatureRenderer(assetStore: store).render(asset: asset,
                                                                                 content: content,
                                                                                 signingTime: signingTime,
                                                                                 rotationDegrees: placement.rotationDegrees)
        } catch {
            throw SigningError.signingFailed("Náhľad grafického podpisu sa nepodarilo vyrenderovať.")
        }

        let field = PDFCoordinateConverter().dssField(placement,
                                                      cropBox: cropBox,
                                                      pageRotation: Int(page.rotation))
        return VisibleSignatureRequest(renderedPNGURL: EnginePaths.canonical(renderedURL),
                                       page: field.page,
                                       originX: Double(field.originX),
                                       originY: Double(field.originY),
                                       width: Double(field.width),
                                       height: Double(field.height),
                                       signingTime: signingTime)
    }

    static func pngDataOrTextFallback(fullName: String, timestamp: Date, provided: Data) -> Data? {
        guard provided.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return nil }
        _ = fullName; _ = timestamp
        return provided
    }

    /// Textová grafika (meno + dátum) keď používateľ nemá vložený obrázok.
    static func textArtworkPNG(fullName: String, timestamp: Date) -> Data {
        let size = NSSize(width: 364, height: 84)
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let name = NSAttributedString(string: fullName, attributes: attributes)
        let bounds = name.boundingRect(with: NSSize(width: size.width, height: size.height - 8),
                                       options: [.usesLineFragmentOrigin])
        name.draw(in: NSRect(x: 0,
                             y: (size.height - bounds.height) / 2,
                             width: size.width,
                             height: ceil(bounds.height)))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }

    // MARK: - Kontajner (ZaKo)

    static func packageContainer(entries: [ASiCEPackager.Entry]) throws -> Data {
        var merged: [String: ASiCEPackager.Entry] = [:]
        for entry in entries {
            merged[entry.path] = entry
        }
        if merged["mimetype"] == nil {
            merged["mimetype"] = ASiCEPackager.Entry(path: "mimetype",
                                                     data: Data(ASiCEPackager.asicMimeType.utf8),
                                                     storeUncompressed: true)
        }
        if merged["META-INF/manifest.xml"] == nil {
            let manifestEntries = merged.values
                .filter { $0.path != "mimetype" && !$0.path.hasPrefix("META-INF/") }
                .sorted { $0.path < $1.path }
                .map { (path: $0.path, mediaType: ASiCEPackager.mediaType(forPath: $0.path)) }
            merged["META-INF/manifest.xml"] = ASiCEPackager.Entry(
                path: "META-INF/manifest.xml",
                data: Data(ASiCEPackager.manifestXML(entries: manifestEntries).utf8))
        }
        return try ASiCEPackager().package(files: Array(merged.values))
    }

    // MARK: - Pomocné

    /// eID SR → QES (nie mandate). Mandátny certifikát je na advokátskom/notárskom
    /// preukaze (I.CA SecureStore a pod.) – detekcia podľa vydávateľa/držiteľa.
    static func isCommercialIssuer(_ issuer: String) -> Bool {
        issuer.lowercased().contains("public ca")
    }

    static func isQualifiedCertificate(issuer: String, displayName: String, qualification: String?) -> Bool {
        if isCommercialIssuer(issuer) { return false }
        if qualification == "QESIG" { return true }
        let text = "\(issuer) \(displayName)".lowercased()
        return text.contains("qualified") || text.contains("qcp") || text.contains("eidas")
            || text.contains("oprávnenie") || text.contains("opravnenie")
    }

    static func isMandateCertificate(issuer: String, displayName: String, qualification: String? = nil) -> Bool {
        if isCommercialIssuer(issuer) { return false }
        let text = "\(issuer) \(displayName)".lowercased()
        if text.contains("oprávnenie") || text.contains("opravnenie")
            || text.contains("mandát") || text.contains("mandat") {
            return true
        }
        return qualification == "QESIG" && text.contains("qualified")
    }

    static func syntheticIdentity(driverNames: [String] = []) -> SigningIdentityInfo {
        let label: String
        if driverNames.isEmpty {
            label = "Podpisová karta (eID / advokátsky preukaz)"
        } else {
            label = "Karta pripojená: \(driverNames.joined(separator: " + "))"
        }
        return SigningIdentityInfo(
            id: "\(syntheticIdentityIDPrefix)\(driverID)",
            label: label,
            issuerSummary: "Zadajte PIN pre načítanie certifikátov",
            isMandateCertificate: false,
            isQualified: true,
            hasPrivateKey: true,
            requiresPIN: true)
    }

    static func identityInfo(from certificate: SigningCertificate) -> SigningIdentityInfo {
        SigningIdentityInfo(
            id: "\(certificateIdentityPrefix)\(certificate.serialNumber)",
            label: certificate.displayName,
            issuerSummary: certificate.issuer,
            validUntil: certificate.validUntil,
            isMandateCertificate: isMandateCertificate(issuer: certificate.issuer,
                                                       displayName: certificate.displayName,
                                                       qualification: certificate.certificateQualification),
            isQualified: isQualifiedCertificate(issuer: certificate.issuer,
                                                displayName: certificate.displayName,
                                                qualification: certificate.certificateQualification),
            hasPrivateKey: true,
            requiresPIN: true)
    }

    static func selectCertificate(from certificates: [SigningCertificate],
                                  preferredSerialNumber: String?) -> SigningCertificate? {
        if let preferredSerialNumber,
           let exact = certificates.first(where: { $0.serialNumber == preferredSerialNumber }) {
            return exact
        }
        return certificates.first { $0.certificateQualification == "QESIG" }
            ?? certificates.first
    }

    static func map(_ failure: SigningFailure) -> SigningError {
        switch failure {
        case .engine(let message):
            return .signingFailed(Self.localizedEngineMessage(message))
        case .fileFailed(let fileID):
            return .signingFailed("Súbor \(fileID) sa nepodarilo podpísať.")
        case .invalidTransition:
            return .signingFailed("Interná chyba podpisového stavu.")
        }
    }

    /// Zjednodušené čitateľné hlásenia pre známe kódy engine-u.
    static func localizedEngineMessage(_ message: String) -> String {
        func code(_ name: String) -> Bool { message.contains("[\(name)]") || message.contains(name) }
        if code("DRIVER_UNAVAILABLE") || code("DRIVER_NOT_FOUND") {
            return "Karta nie je dostupná — vložte ju do čítačky a skúste znova."
        }
        if code("PIN_INCORRECT") {
            return "Nesprávny PIN alebo BOK."
        }
        if code("CERTIFICATE_NOT_FOUND") || code("CERTIFICATE_AMBIGUOUS") {
            return "Zvolený certifikát už nie je na karte — obnovte zoznam certifikátov."
        }
        if code("TIMESTAMP_FAILED") {
            return "Nepodarilo sa získať kvalifikovanú časovú pečiatku (TSA)."
        }
        if code("OUTPUT_VALIDATION_FAILED") {
            return "Engine odmietol výsledok podpisu (výstupná validácia)."
        }
        return message
    }

    /// Mapovanie ostatných chýb bridge vrstvy (session proces, launcher).
    static func mapAny(_ error: Error) -> SigningError {
        if let failure = error as? SigningFailure {
            return map(failure)
        }
        if let sessionFailure = error as? MachineSessionProcessFailure {
            switch sessionFailure {
            case .launchFailed:
                return .signingFailed("Engine sa nepodarilo spustiť (AutogramCLI helper).")
            case .malformedOutput:
                return .signingFailed("Engine vrátil nečitateľnú odpoveď.")
            case .helperExited(let status):
                return .signingFailed("Engine proces sa ukončil (exit \(status)).")
            case .requestFailed(let code):
                return .signingFailed(localizedEngineMessage("The machine request could not be completed. [\(code)]"))
            case .cancelled:
                return .signingFailed("Podpisovanie bolo zrušené.")
            }
        }
        if error is CancellationError {
            return .signingFailed("Podpisovanie bolo zrušené.")
        }
        return .signingFailed(error.localizedDescription)
    }

    static func hasVisibleSignatureField(in pdf: Data) -> Bool {
        guard let sig = pdf.range(of: Data("/FT /Sig".utf8)) else { return false }
        let window = pdf[sig.lowerBound..<min(pdf.endIndex, sig.lowerBound + 400)]
        let text = String(decoding: window, as: UTF8.self)
        if text.contains("[0.0 0.0 0.0 0.0]") || text.contains("[0 0 0 0]") { return false }
        return text.contains("/Rect")
    }

    static func makeWorkspace(fileManager: FileManager = .default) throws -> URL {
        let temporary = EnginePaths.canonical(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        let directory = temporary
            .appendingPathComponent("autogram-engine", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func statusLog(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
