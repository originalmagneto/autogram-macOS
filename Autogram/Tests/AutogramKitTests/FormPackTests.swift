import XCTest
@testable import AutogramKit

final class FormPackTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func pack(
        id: String = "test-pack",
        direction: ConversionDirection = .paperToElectronic,
        effectiveFrom: Date = Date(timeIntervalSince1970: 0),
        effectiveUntil: Date? = nil,
        verificationState: FormPackVerificationState = .verified,
        acceptanceState: FormPackAcceptanceState = .accepted,
        renderer: FormPackRenderer = .legacySwift,
        format: ZakoCodelistItem = ZakoCodelists.pdfa2FormatItem
    ) -> ConversionFormPack {
        ConversionFormPack(
            id: id,
            direction: direction,
            recordVersion: "1.0",
            clauseVersion: "1.0",
            namespace: "https://example.invalid/\(id)",
            eFormIdentifier: "example/\(id)",
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
            verificationState: verificationState,
            acceptanceState: acceptanceState,
            renderer: renderer,
            recordSchema: .init(resourceName: "record.xsd", sha256Hex: String(repeating: "a", count: 64)),
            clauseSchema: .init(resourceName: "clause.xsd", sha256Hex: String(repeating: "b", count: 64)),
            stylesheet: .init(resourceName: "clause.xsl", sha256Hex: String(repeating: "c", count: 64)),
            codelists: .init(resourceName: "codelists.json", sha256Hex: String(repeating: "d", count: 64)),
            newDocumentFormatItem: format,
            fingerprintMethodItem: ZakoCodelists.sha256Item)
    }

    func testCurrentPackIsExplicitlyPilotOnly() {
        let current = FormPackRepository.currentLegacyUnverified

        XCTAssertEqual(current.verificationState, .unverified)
        XCTAssertEqual(current.acceptanceState, .unknown)
        XCTAssertFalse(current.isProductionEligible)
        XCTAssertFalse(current.recordSchema.isPresent)
        XCTAssertFalse(current.clauseSchema.isPresent)
        XCTAssertFalse(current.stylesheet.isPresent)
        XCTAssertFalse(current.codelists.isPresent)
    }

    func testProductionPolicyRejectsCurrentPack() {
        let repository = FormPackRepository()

        XCTAssertThrowsError(try repository.pack(
            for: .paperToElectronic,
            at: referenceDate,
            policy: .requireVerified)) { error in
            XCTAssertEqual(error as? FormPackError,
                           .unverifiedPack(packID: FormPackRepository.currentLegacyUnverified.id))
        }
    }

    func testPilotPolicyReturnsCurrentPack() throws {
        let selected = try FormPackRepository().pack(
            for: .paperToElectronic,
            at: referenceDate,
            policy: .allowUnverifiedPilot)

        XCTAssertEqual(selected.id, FormPackRepository.currentLegacyUnverified.id)
    }

    func testEffectiveIntervalUsesInclusiveStartAndExclusiveEnd() throws {
        let bounded = pack(effectiveFrom: referenceDate,
                           effectiveUntil: referenceDate.addingTimeInterval(60))
        let repository = FormPackRepository(packs: [bounded])

        XCTAssertEqual(try repository.pack(for: .paperToElectronic,
                                           at: referenceDate,
                                           policy: .requireVerified).id,
                       bounded.id)
        XCTAssertThrowsError(try repository.pack(for: .paperToElectronic,
                                                 at: referenceDate.addingTimeInterval(60),
                                                 policy: .requireVerified))
    }

    func testOverlappingActivePacksAreRejected() {
        let first = pack(id: "first")
        let second = pack(id: "second")
        let repository = FormPackRepository(packs: [first, second])

        XCTAssertThrowsError(try repository.pack(for: .paperToElectronic,
                                                 at: referenceDate,
                                                 policy: .requireVerified)) { error in
            XCTAssertEqual(error as? FormPackError,
                           .multipleMatchingPacks(direction: .paperToElectronic, date: referenceDate))
        }
    }

    func testHistoricalLookupIsIndependentOfActiveSelection() throws {
        let historical = pack(id: "historical", effectiveUntil: referenceDate)
        let active = pack(id: "active", effectiveFrom: referenceDate)
        let repository = FormPackRepository(packs: [historical, active])

        XCTAssertEqual(repository.pack(id: historical.id), historical)
        XCTAssertEqual(try repository.pack(for: .paperToElectronic,
                                           at: referenceDate,
                                           policy: .requireVerified).id,
                       active.id)
    }

    func testPackManifestRoundTripsThroughCodable() throws {
        let original = pack()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversionFormPack.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.recordSchema.sha256Hex?.count, 64)
    }

    func testStampCapturesPackProvenance() {
        let stamp = FormPackStamp(pack: FormPackRepository.currentLegacyUnverified)

        XCTAssertEqual(stamp.packID, "autogram-p2e-legacy-swift-1.0")
        XCTAssertEqual(stamp.recordVersion, "1.0")
        XCTAssertEqual(stamp.verificationState, .unverified)
        XCTAssertEqual(stamp.acceptanceState, .unknown)
        XCTAssertEqual(stamp.outputFormatCode, "PDFA2")
    }

    func testEnvelopePreservesPackProvenanceThroughCodable() throws {
        let pack = FormPackRepository.currentLegacyUnverified
        let envelope = ConversionRecordEnvelope(
            evidenceNumber: "1563-231114-1",
            direction: .paperToElectronic,
            originalName: "a",
            newDocumentName: "b",
            attestationXML: "<ConversionRecord/>",
            fingerprintSHA256Hex: String(repeating: "a", count: 64),
            conversionTime: referenceDate,
            formPack: FormPackStamp(pack: pack))

        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ConversionRecordEnvelope.self, from: encoded)

        XCTAssertEqual(decoded.formPack, envelope.formPack)
        XCTAssertEqual(decoded.formPack?.packID, pack.id)
    }

    func testProposedOutputProfilesRemainExplicitlyUnavailable() {
        XCTAssertFalse(ConversionOutputProfile.proposedPDFA1a.isImplemented)
        XCTAssertFalse(ConversionOutputProfile.proposedSinglePagePNG.isImplemented)
        XCTAssertFalse(ConversionOutputProfile.proposedPDFA1a.isExternallyVerified)
        XCTAssertFalse(ConversionOutputProfile.proposedSinglePagePNG.isExternallyVerified)
        XCTAssertEqual(ConversionOutputProfile.pilotPDFA2b.pdfaPart, 2)
        XCTAssertEqual(ConversionOutputProfile.pilotPDFA2b.pdfaConformance, "B")
    }

    func testProductionEligibilityRequiresBothVerificationAndAcceptance() {
        let verifiedButUnknown = pack(acceptanceState: .unknown)
        let acceptedButUnverified = pack(verificationState: .unverified)

        XCTAssertFalse(verifiedButUnknown.isProductionEligible)
        XCTAssertFalse(acceptedButUnverified.isProductionEligible)
        XCTAssertTrue(pack().isProductionEligible)
    }
}