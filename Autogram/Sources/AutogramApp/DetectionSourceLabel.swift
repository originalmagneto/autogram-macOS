import Foundation

/// Turns the technical `detectionSource` audit string into something a notary
/// can read. The stored string stays untouched: it is evidence.
enum DetectionSourceLabel {
    private static let replacements: [(needle: String, slovak: String)] = [
        ("builtInHint", "iba odhad heuristiky"),
        ("builtIn", "heuristika"),
        ("contour", "kontúry"),
        ("saliency", "saliency"),
        ("fm", "on-device model")
    ]

    static func slovak(_ source: String?) -> String {
        guard let source, !source.isEmpty else { return "Označené ručne" }
        var result = source
        // "kNN(n=5)" carries a count, so it is rewritten by pattern rather than
        // by literal replacement.
        if let range = result.range(of: #"kNN\(n=(\d+)\)"#, options: .regularExpression) {
            let match = String(result[range])
            let digits = match.filter { $0.isNumber }
            result.replaceSubrange(range, with: "porovnanie s \(digits) príkladmi")
        }
        // `builtInHint` must be matched before `builtIn`, hence the ordered list.
        for replacement in replacements {
            result = result.replacingOccurrences(of: replacement.needle, with: replacement.slovak)
        }
        return result
    }
}
