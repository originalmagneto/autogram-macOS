import Foundation
import AppKit

enum VisualSignatureAppearance {
    static let textID = "text"
}

enum VisualSignatureStore {
    struct Item: Identifiable, Hashable {
        var id: String
        var name: String
    }

    static func directory() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Autogram/Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func items() -> [Item] {
        var result = [Item(id: VisualSignatureAppearance.textID, name: "Textový (meno + dátum)")]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory(),
            includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where ["png", "jpg", "jpeg", "tif", "tiff", "heic"].contains(file.pathExtension.lowercased()) {
            result.append(Item(id: file.lastPathComponent,
                               name: file.deletingPathExtension().lastPathComponent))
        }
        return result
    }

    static func imageData(for id: String) -> Data? {
        guard id != VisualSignatureAppearance.textID else { return nil }
        let url = directory().appendingPathComponent(id)
        return try? Data(contentsOf: url)
    }

    static func importImage(from url: URL) -> String? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        var filename = "\(name).\(ext)"
        var index = 2
        while FileManager.default.fileExists(atPath: directory().appendingPathComponent(filename).path) {
            filename = "\(name)-\(index).\(ext)"
            index += 1
        }
        let dest = directory().appendingPathComponent(filename)
        do {
            try data.write(to: dest, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }
}
