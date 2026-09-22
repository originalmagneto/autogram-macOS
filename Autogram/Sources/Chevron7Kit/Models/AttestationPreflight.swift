// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public enum AttestationPreflight {
    public struct Result: Equatable, Sendable {
        public let errors: [AttestationValidationError]
        public let hasSelectedIdentity: Bool
        public let mandateRequirementSatisfied: Bool
        public let unreviewedNonEmptyPages: [Int]

        public var isComplete: Bool {
            errors.isEmpty && hasSelectedIdentity && mandateRequirementSatisfied && unreviewedNonEmptyPages.isEmpty
        }

        public init(
            errors: [AttestationValidationError],
            hasSelectedIdentity: Bool,
            mandateRequirementSatisfied: Bool,
            unreviewedNonEmptyPages: [Int] = []
        ) {
            self.errors = errors
            self.hasSelectedIdentity = hasSelectedIdentity
            self.mandateRequirementSatisfied = mandateRequirementSatisfied
            self.unreviewedNonEmptyPages = unreviewedNonEmptyPages
        }
    }

    public static func evaluate(
        _ data: AttestationData,
        securityElements: [SecurityElement],
        hasSelectedIdentity: Bool,
        mandateRequirementSatisfied: Bool,
        inputSignatureInspection: InputSignatureInspectionResult,
        unreviewedNonEmptyPages: [Int] = [],
        documentPageCount: Int? = nil
    ) -> Result {
        let pendingCount = securityElements.filter { $0.reviewState == .pending }.count
        var errors = AttestationValidator.validate(
            data,
            securityElements: securityElements.filter { $0.reviewState == .confirmed },
            qualifiedTimestampTime: nil)
        if let documentPageCount, securityElements.contains(where: {
            $0.reviewState == .confirmed && $0.observation == .physicalOriginal
                && ($0.newDocumentPageIndex ?? -1) >= documentPageCount
        }) { errors.append(.physicalElementOutputPageRequired) }
        if inputSignatureInspection.state != .valid {
            errors.append(.inputSignatureVerificationRequired(
                state: inputSignatureInspection.state))
        }
        if pendingCount > 0 {
            errors.append(.securityElementsNeedReview(count: pendingCount))
        }
        if !unreviewedNonEmptyPages.isEmpty {
            errors.append(.unreviewedNonEmptyPages(pages: unreviewedNonEmptyPages))
        }
        return Result(
            errors: errors,
            hasSelectedIdentity: hasSelectedIdentity,
            mandateRequirementSatisfied: mandateRequirementSatisfied,
            unreviewedNonEmptyPages: unreviewedNonEmptyPages)
    }
}