// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class FormSchemaValidatorTests: XCTestCase {
    private let validator = FormSchemaValidator()

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    func testWrongRootIsReportedAsInvalid() {
        let xml = Data("<Nothing xmlns=\"\(OfficialForm.clause_1_3.namespace)\"/>".utf8)
        XCTAssertThrowsError(try validator.validate(xml, against: .clause_1_3)) { error in
            guard case FormSchemaValidator.Failure.invalid(let details) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(details.contains("Nothing"), details)
        }
    }

    func testMissingValidatorIsReported() {
        let missing = FormSchemaValidator(xmllintURL: URL(fileURLWithPath: "/nonexistent/xmllint"))
        XCTAssertThrowsError(try missing.validate(Data("<a/>".utf8), against: .clause_1_3)) { error in
            XCTAssertEqual(error as? FormSchemaValidator.Failure, .validatorUnavailable)
        }
    }
}
