import Foundation
import PDFKit
import SwiftUI
import AutogramKit

@MainActor
@Observable
final class SigningSessionStore {
    enum Step: Int, CaseIterable { case intake = 0, prepare = 1, done = 2 }

    var step: Step = .intake
    var sourceURL: URL?
    var document: PDFDocument?
    var analysis: DocumentAnalysis = .empty()
    var isAnalyzing = false

    var identities: [SigningIdentityInfo] = []
    var selectedIdentityID: String?

    var includeQualifiedTimestamp = true
    var includeVisibleSignature = true
    var signaturePage: Int = 0
    var signatureRect = NormalizedRect(x: 0.58, y: 0.80, width: 0.30, height: 0.09)

    var isSigning = false
    var statusText = ""
    var result: SignedConversionResult?
    var outputDirectory: URL?
    var lastError: String?

    let signingProvider: any QualifiedSigningProviding
    let stamper = VisibleSignatureStamper()

    init(signingProvider: any QualifiedSigningProviding) {
        self.signingProvider = signingProvider
    }

    func loadDocument(at url: URL) async {
        lastError = nil
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            lastError = "Súbor sa nepodarilo otvoriť ako PDF."
            return
        }
        self.document = document
        self.sourceURL = url
        step = .prepare
        isAnalyzing = true
        let engine = PDFAnalysisEngine()
        analysis = await Task.detached(priority: .userInitiated) {
            engine.analyze(document: document)
        }.value
        signaturePage = max(analysis.totalPages - 1, 0)
        isAnalyzing = false
        await refreshIdentities()
    }

    func refreshIdentities() async {
        identities = await signingProvider.availableIdentities()
        if selectedIdentityID == nil || !identities.contains(where: { $0.id == selectedIdentityID }) {
            selectedIdentityID = identities.first(where: { $0.isMandateCertificate })?.id
                ?? identities.first?.id
        }
    }

    var canSign: Bool {
        document != nil && selectedIdentityID != nil && !isSigning
    }

    func sign() async {
        guard let document else { return }
        lastError = nil
        isSigning = true
        statusText = includeVisibleSignature ? "Pripravujem vizuálny podpis…" : "Podpisujem…"

        do {
            var pdfData = try await Task.detached(priority: .userInitiated) {
                document.dataRepresentation()
            }.get() ?? Data()

            if includeVisibleSignature, !pdfData.isEmpty {
                statusText = "Vkladám vizuálny podpis…"
                let stamp = VisibleSignatureStamper.StampData(
                    fullName: displayName(),
                    timestamp: Date(),
                    pageIndex: min(signaturePage, analysis.totalPages - 1),
                    normalizedRect: signatureRect)
                let includeStamp = includeQualifiedTimestamp
                if let stampedData = await Task.detached(priority: .userInitiated) { [stamper] in
                    stamper.stamp(document: PDFDocument(data: pdfData) ?? document,
                                  stamp: stamp,
                                  includeTimestamp: includeStamp)
                }.get(), let stampedDoc = PDFDocument(data: stampedData),
                   let finalData = stampedDoc.dataRepresentation() {
                    pdfData = finalData
                }
            }

            statusText = "Podpisujem kvalifikovaným podpisom…"
            guard let identityID = selectedIdentityID else {
                throw SigningError.identityUnavailable
            }
            let signed = try await signingProvider.sign(pdf: pdfData,
                                                        identityID: identityID,
                                                        includeTimestamp: includeQualifiedTimestamp)

            statusText = "Ukladám…"
            let directory = Self.outputDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let baseName = "\(formatter.string(from: Date()))-podpisane"
            let target = directory.appendingPathComponent("\(baseName).pdf")
            try signed.pdfData.write(to: target, options: [.atomic])
            if let asic = signed.asicData {
                try asic.write(to: directory.appendingPathComponent("\(baseName).asice"),
                               options: [.atomic])
            }
            outputDirectory = directory

            result = signed
            statusText = ""
            step = .done
        } catch {
            lastError = error.localizedDescription
            statusText = ""
        }
        isSigning = false
    }

    private func displayName() -> String {
        if let identity = identities.first(where: { $0.id == selectedIdentityID }),
           identity.label != "DEMO podpis (vývojový režim)" {
            return identity.label
        }
        return "Elektronický podpis Autogram"
    }

    func reset(keepingIdentity: Bool = true) {
        let identity = keepingIdentity ? selectedIdentityID : nil
        step = .intake
        sourceURL = nil
        document = nil
        analysis = .empty()
        result = nil
        outputDirectory = nil
        lastError = nil
        isAnalyzing = false
        selectedIdentityID = identity
    }

    static func outputDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Autogram/Output", isDirectory: true)
    }
}
