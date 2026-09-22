import Foundation
import XCTest
@testable import Chevron7Kit

final class EZZKEvidenceNumberPolicyTests: XCTestCase {
    func testOldSettingsDecodeToDemoWithoutPersonName() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.ezzkMode, .demo)
        XCTAssertEqual(settings.ezzkPersonName, "")
    }

    func testEZZKModeAndPersonNameRoundTrip() throws {
        var settings = AppSettings()
        settings.ezzkMode = .test
        settings.ezzkPersonName = "Advokátska kancelária Test"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.ezzkMode, .test)
        XCTAssertEqual(decoded.ezzkPersonName, "Advokátska kancelária Test")
        XCTAssertEqual(AppSettings.EZZKMode.demo.environment, nil)
        XCTAssertEqual(AppSettings.EZZKMode.test.environment, .sandbox)
        XCTAssertEqual(AppSettings.EZZKMode.production.environment, .production)
    }

    func testAttestationKeepsAllocationTimeAndOldDataDecodesWithoutIt() throws {
        var attestation = AttestationData()
        attestation.evidenceNumber = "260917-A"
        attestation.evidenceNumberAllocatedAt = Date(timeIntervalSince1970: 1_789_624_800)
        attestation.evidenceNumberMode = .test
        let data = try JSONEncoder().encode(attestation)
        let decoded = try JSONDecoder().decode(AttestationData.self, from: data)
        XCTAssertEqual(decoded.evidenceNumberAllocatedAt, Date(timeIntervalSince1970: 1_789_624_800))
        XCTAssertEqual(decoded.evidenceNumberMode, .test)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "evidenceNumberAllocatedAt")
        object.removeValue(forKey: "evidenceNumberMode")
        let old = try JSONSerialization.data(withJSONObject: object)
        let oldDecoded = try JSONDecoder().decode(AttestationData.self, from: old)
        XCTAssertNil(oldDecoded.evidenceNumberAllocatedAt)
        XCTAssertNil(oldDecoded.evidenceNumberMode)
    }

    func testAttestationWithoutModeDoesNotEncodeIt() throws {
        let data = try JSONEncoder().encode(AttestationData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["evidenceNumberMode"])
    }

    func testNumberIsUsableOnlyInTheModeThatFetchedIt() {
        XCTAssertTrue(EZZKEvidenceNumberPolicy.isFromCurrentMode(numberMode: .demo, currentMode: .demo))
        XCTAssertTrue(EZZKEvidenceNumberPolicy.isFromCurrentMode(numberMode: .test, currentMode: .test))
        XCTAssertFalse(EZZKEvidenceNumberPolicy.isFromCurrentMode(numberMode: .demo, currentMode: .test))
        XCTAssertFalse(EZZKEvidenceNumberPolicy.isFromCurrentMode(numberMode: .demo, currentMode: .production))
        XCTAssertFalse(EZZKEvidenceNumberPolicy.isFromCurrentMode(numberMode: .test, currentMode: .production))
        // A number typed by hand or from older data carries no mode and is not judged.
        XCTAssertTrue(EZZKEvidenceNumberPolicy.isFromCurrentMode(numberMode: nil, currentMode: .production))
    }

    func testNumberIsUsableOnlyOnItsBratislavaAllocationDay() {
        // 2026-09-17 06:00Z (08:00 CEST) and 21:00Z (23:00 CEST) are the same Slovak day.
        XCTAssertTrue(EZZKEvidenceNumberPolicy.isUsable(
            allocatedAt: Date(timeIntervalSince1970: 1_789_624_800), at: Date(timeIntervalSince1970: 1_789_678_800)))
        // 21:30Z is 23:30 CEST; 22:10Z is 00:10 CEST on the next day.
        XCTAssertFalse(EZZKEvidenceNumberPolicy.isUsable(
            allocatedAt: Date(timeIntervalSince1970: 1_789_680_600), at: Date(timeIntervalSince1970: 1_789_683_000)))
        XCTAssertTrue(EZZKEvidenceNumberPolicy.isUsable(allocatedAt: nil, at: Date()))
    }

    func testPersonNameFollowsTheClause() {
        let office = AdvocateProfile(fullName: "JUDr. Ján Novák", ico: "42249180",
                                     officeName: "Advokátska kancelária Test", isLegalEntity: true)
        let natural = AdvocateProfile(fullName: "JUDr. Ján Novák", ico: "12345678")
        XCTAssertEqual(EZZKEvidenceNumberPolicy.personName(for: office), "Advokátska kancelária Test")
        XCTAssertEqual(EZZKEvidenceNumberPolicy.personName(for: natural), "JUDr. Ján Novák")
    }

    func testIdentityMismatch() {
        let clause = AdvocateProfile(fullName: "JUDr. Ján Novák", ico: "42249180",
                                     officeName: "Advokátska kancelária Test", isLegalEntity: true)
        XCTAssertNil(EZZKEvidenceNumberPolicy.identityMismatch(
            clausePerson: clause, accountName: "advokátska  kancelária TEST", accountICO: "000042249180"))
        XCTAssertNil(EZZKEvidenceNumberPolicy.identityMismatch(clausePerson: clause, accountName: "", accountICO: ""))

        let nameWarning = EZZKEvidenceNumberPolicy.identityMismatch(
            clausePerson: clause, accountName: "Iná kancelária", accountICO: "42249180")
        XCTAssertEqual(nameWarning,
                       "Doložka nezodpovedá EZZK účtu: názov osoby v doložke „Advokátska kancelária Test“ sa líši od EZZK účtu „Iná kancelária“.")

        let icoWarning = EZZKEvidenceNumberPolicy.identityMismatch(
            clausePerson: clause, accountName: "Advokátska kancelária Test", accountICO: "11111111")
        XCTAssertEqual(icoWarning,
                       "Doložka nezodpovedá EZZK účtu: IČO v doložke „42249180“ sa líši od IČO EZZK účtu „11111111“.")
    }
}
