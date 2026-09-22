import Foundation

/// Resolves the file a drop came from.
///
/// `NSItemProvider` hands a dropped file URL over in one of three shapes
/// depending on the source: a `URL`, an `NSURL`, or the URL's data
/// representation. Reading the drop as bytes instead loses both the location and
/// the name, which sends the signed output to a temporary directory under a
/// generated name. Everything that accepts a drop resolves the URL first and
/// falls back to bytes only when the drop carries no file.
enum DroppedFileURL {
    static func resolve(from item: Any?) -> URL? {
        let url: URL?
        switch item {
        case let value as URL:
            url = value
        case let value as NSURL:
            url = value as URL
        case let value as Data:
            url = URL(dataRepresentation: value, relativeTo: nil)
        default:
            url = nil
        }
        guard let url, url.isFileURL else { return nil }
        return url
    }
}
