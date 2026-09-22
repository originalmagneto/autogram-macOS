// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

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

    /// `directory` is `AppSettingsStore.signaturesDirectory`; it is created on first use.
    static func directory(_ directory: URL) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func items(in signatures: URL) -> [Item] {
        var result = [Item(id: VisualSignatureAppearance.textID, name: "Textový (meno + dátum)")]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory(signatures),
            includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where ["png", "jpg", "jpeg", "tif", "tiff", "heic"].contains(file.pathExtension.lowercased()) {
            result.append(Item(id: file.lastPathComponent,
                               name: file.deletingPathExtension().lastPathComponent))
        }
        return result
    }

    static func imageData(for id: String, in signatures: URL) -> Data? {
        guard id != VisualSignatureAppearance.textID else { return nil }
        let url = directory(signatures).appendingPathComponent(id)
        return try? Data(contentsOf: url)
    }

    static func importImage(from url: URL, into signatures: URL) -> String? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        var filename = "\(name).\(ext)"
        var index = 2
        while FileManager.default.fileExists(atPath: directory(signatures).appendingPathComponent(filename).path) {
            filename = "\(name)-\(index).\(ext)"
            index += 1
        }
        let dest = directory(signatures).appendingPathComponent(filename)
        do {
            try data.write(to: dest, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }
}
