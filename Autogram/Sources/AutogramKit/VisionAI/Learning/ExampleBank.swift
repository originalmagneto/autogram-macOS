import Foundation

public enum BankLabel: Codable, Hashable, Sendable {
    case kind(SecurityElement.Kind)
    case negative

    public var exportLabel: String {
        switch self {
        case .negative: return "negative"
        case .kind(let kind):
            switch kind {
            case .handwrittenSignature: return "handwrittenSignature"
            case .officialStamp: return "officialStamp"
            case .embossedSeal: return "embossedSeal"
            case .initial: return "initial"
            case .other: return "other"
            }
        }
    }
}

public struct BankEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var label: BankLabel
    public var documentSHA256: String
    public var pageIndex: Int
    public var box: NormalizedRect
    public var featureVector: FeatureVector
    public var createdAt: Date
    public var detectorVersion: String

    public init(id: UUID = UUID(), label: BankLabel, documentSHA256: String, pageIndex: Int,
                box: NormalizedRect, featureVector: FeatureVector, createdAt: Date = Date(),
                detectorVersion: String) {
        self.id = id
        self.label = label
        self.documentSHA256 = documentSHA256
        self.pageIndex = pageIndex
        self.box = box
        self.featureVector = featureVector
        self.createdAt = createdAt
        self.detectorVersion = detectorVersion
    }

    public var pageImageFileName: String { "\(documentSHA256)-p\(pageIndex).png" }
    public var cropImageFileName: String { "\(id.uuidString).png" }
}

/// Local, on-device store of reviewed crops. JSON index plus PNG files.
public actor ExampleBank {
    public let directory: URL
    private var cache: [BankEntry] = []
    private var loaded = false

    public init(directory: URL) { self.directory = directory }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Autogram/VisionBank", isDirectory: true)
    }

    public var indexURL: URL { directory.appendingPathComponent("bank.json") }
    public var pagesDirectory: URL { directory.appendingPathComponent("pages", isDirectory: true) }
    public var cropsDirectory: URL { directory.appendingPathComponent("crops", isDirectory: true) }

    public func load() throws {
        try FileManager.default.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cropsDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([BankEntry].self, from: data)
        } else {
            cache = []
        }
        loaded = true
    }

    private func ensureLoaded() throws {
        if !loaded { try load() }
    }

    public func entries() -> [BankEntry] {
        try? ensureLoaded()
        return cache
    }

    public func count(for label: BankLabel) -> Int {
        entries().filter { $0.label == label }.count
    }

    public func add(_ entry: BankEntry) throws {
        try ensureLoaded()
        cache.removeAll { $0.id == entry.id }
        cache.append(entry)
        try persist()
    }

    public func remove(id: UUID) throws {
        try ensureLoaded()
        cache.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: cropsDirectory.appendingPathComponent("\(id.uuidString).png"))
        try persist()
    }

    public func removeAll() throws {
        cache = []
        try? FileManager.default.removeItem(at: directory)
        loaded = false
        try load()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: indexURL, options: .atomic)
    }
}
