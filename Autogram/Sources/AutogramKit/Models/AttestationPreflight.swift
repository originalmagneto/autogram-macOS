import Foundation

public enum AttestationPreflight {
    public struct Result: Equatable, Sendable {
        public let errors: [AttestationValidationError]
        public let hasSelectedIdentity: Bool
        public let mandateRequirementSatisfied: Bool

        public var isComplete: Bool {
            errors.isEmpty && hasSelectedIdentity && mandateRequirementSatisfied
        }

        public init(
            errors: [AttestationValidationError],
            hasSelectedIdentity: Bool,
            mandateRequirementSatisfied: Bool
        ) {
            self.errors = errors
            self.hasSelectedIdentity = hasSelectedIdentity
            self.mandateRequirementSatisfied = mandateRequirementSatisfied
        }
    }

    public static func evaluate(
        _ data: AttestationData,
        securityElements: [SecurityElement],
        hasSelectedIdentity: Bool,
        mandateRequirementSatisfied: Bool
    ) -> Result {
        Result(
            errors: AttestationValidator.validate(
                data,
                securityElements: securityElements,
                qualifiedTimestampTime: nil),
            hasSelectedIdentity: hasSelectedIdentity,
            mandateRequirementSatisfied: mandateRequirementSatisfied)
    }
}
