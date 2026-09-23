// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class AttestationValidatorLocationTests: XCTestCase {
    private func errors(location: String) -> [AttestationValidationError] {
        var element = ConversionFormModelTests.scanElement()
        element.observation = .physicalOriginal
        element.originalLocation = location
        element.newDocumentPageIndex = 0
        return AttestationValidator.validate(ConversionFormModelTests.attestation(),
                                             securityElements: [element], qualifiedTimestampTime: nil)
    }

    func testFreeTextLocationNeedsACodelistChoice() {
        XCTAssertTrue(errors(location: "vpravo dole pri podpise").contains(.physicalElementLocationRequired))
    }

    func testCodelistLocationIsAccepted() {
        XCTAssertFalse(errors(location: "Right down").contains(.physicalElementLocationRequired))
    }
}
