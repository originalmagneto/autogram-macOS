import Chevron7Identity
import Foundation

public enum BankLabel: Codable, Hashable, Sendable {
    case kind(SecurityElement.Kind)
    case negative

    public var exportLabel: String {
        switch self {
        case .negative: return "negative"
        case .kind(let kind): return kind.trainingLabel
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

public struct ReviewedPageBox: Codable, Sendable, Equatable {
    public var kind: SecurityElement.Kind
    public var box: NormalizedRect
}

/// A complete human review, independent of the partial crop-learning bank.
public struct ReviewedBankPage: Codable, Sendable, Equatable {
    public var documentSHA256: String
    public var pageIndex: Int
    public var boxes: [ReviewedPageBox]
    public var reviewedAt: Date
    public var detectorVersion: String
    public var pageImageFileName: String { "\(documentSHA256)-p\(pageIndex).png" }
}

/// Local, on-device store of reviewed crops. JSON index plus PNG files.
public actor ExampleBank {
    public let directory: URL
    private var cache: [BankEntry] = []
    private var pageCache: [ReviewedBankPage] = []
    private var loaded = false
    public private(set) var loadError: Error?

    public init(directory: URL) { self.directory = directory }

    public static var defaultDirectory: URL {
        ProductIdentity.applicationSupportDirectory().appendingPathComponent("VisionBank", isDirectory: true)
    }

    public var indexURL: URL { directory.appendingPathComponent("bank.json") }
    public var reviewedPagesURL: URL { directory.appendingPathComponent("reviewed-pages.json") }
    public var pagesDirectory: URL { directory.appendingPathComponent("pages", isDirectory: true) }
    public var cropsDirectory: URL { directory.appendingPathComponent("crops", isDirectory: true) }

    public func load() throws {
        try FileManager.default.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cropsDirectory, withIntermediateDirectories: true)
        loadError = nil
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                cache = try decoder.decode([BankEntry].self, from: data)
                loadError = nil
            } catch {
                cache = []
                loadError = error
            }
        } else {
            cache = []
        }
        pageCache = []
        if FileManager.default.fileExists(atPath: reviewedPagesURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do { pageCache = try decoder.decode([ReviewedBankPage].self, from: Data(contentsOf: reviewedPagesURL)) }
            catch { loadError = error }
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
        if let previous = cache.first(where: { $0.id == entry.id }) {
            try invalidateReviewedPage(documentSHA256: previous.documentSHA256, pageIndex: previous.pageIndex)
        }
        try invalidateReviewedPage(documentSHA256: entry.documentSHA256, pageIndex: entry.pageIndex)
        cache.removeAll { $0.id == entry.id }
        cache.append(entry)
        try persist()
    }

    public func remove(id: UUID) throws {
        try ensureLoaded()
        for entry in cache where entry.id == id {
            try invalidateReviewedPage(documentSHA256: entry.documentSHA256, pageIndex: entry.pageIndex)
        }
        cache.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: cropsDirectory.appendingPathComponent("\(id.uuidString).png"))
        try persist()
    }

    public func reviewedPages() throws -> [ReviewedBankPage] {
        try ensureLoaded()
        if let loadError { throw loadError }
        return pageCache
    }

    func saveReviewedPage(_ page: ReviewedBankPage) throws {
        try ensureLoaded()
        pageCache.removeAll { $0.documentSHA256 == page.documentSHA256 && $0.pageIndex == page.pageIndex }
        pageCache.append(page)
        try persistReviewedPages()
    }

    public func invalidateReviewedPage(documentSHA256: String, pageIndex: Int) throws {
        try ensureLoaded()
        pageCache.removeAll { $0.documentSHA256 == documentSHA256 && $0.pageIndex == pageIndex }
        try persistReviewedPages()
    }

    public func removeAll() throws {
        cache = []
        pageCache = []
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

    private func persistReviewedPages() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pageCache).write(to: reviewedPagesURL, options: .atomic)
    }
}
