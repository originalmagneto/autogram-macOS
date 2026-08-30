import Foundation

public struct EZZKAvailableEvidenceResponse: Codable, Sendable, Equatable {
    public let availableEvidenceNumbers: [String]
    public let description: String?

    public init(availableEvidenceNumbers: [String], description: String? = nil) {
        self.availableEvidenceNumbers = availableEvidenceNumbers
        self.description = description
    }
}

public struct EZZKFilePayload: Codable, Sendable, Equatable {
    public let fileName: String
    public let fileType: String
    public let value: String

    public init(fileName: String, fileType: String, value: String) {
        self.fileName = fileName
        self.fileType = fileType
        self.value = value
    }
}

public struct EZZKFilesRequest: Codable, Sendable, Equatable {
    public let files: [EZZKFilePayload]

    public init(files: [EZZKFilePayload]) {
        self.files = files
    }
}

public struct EZZKSubmissionReceipt: Codable, Sendable, Equatable {
    public let receipt: String

    public init(receipt: String) {
        self.receipt = receipt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .receipt)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .receipt, in: container, debugDescription: "Receipt is empty")
        }
        receipt = value
    }

    private enum CodingKeys: String, CodingKey {
        case receipt
    }
}
