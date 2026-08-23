import Foundation

public struct TimestampAuthority: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    public var id: String { url }

    public static let legacyDefaultURL = "http://tsa.disig.sk/qts"

    public static let builtIn: [TimestampAuthority] = [
        TimestampAuthority(name: "CA Disig (SK)", url: "http://tsa.disig.sk/qts"),
        TimestampAuthority(name: "Sectigo Qualified", url: "http://timestamp.sectigo.com/qualified"),
        TimestampAuthority(name: "Belgian Federal Government TSA", url: "http://tsa.belgium.be/connect")
    ]

    public static func resolveSelected(customServers: [String], selectedTSAURL: String)
        -> [TimestampAuthority] {
        var all = builtIn
        for raw in customServers where !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let server = raw.trimmingCharacters(in: .whitespaces)
            if !all.contains(where: { $0.url.caseInsensitiveCompare(server) == .orderedSame }) {
                all.append(TimestampAuthority(name: server, url: server))
            }
        }
        return all
    }
}
