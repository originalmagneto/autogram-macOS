import Foundation

/// Canonicalizácia ciest pre Java validátor (strict real-path kontrola).
/// Foundation API (resolvingSymlinksInPath / standardizingPath) NEriešia /var → /private/var.
public enum EnginePaths {
    /// Reálny canonical path cez realpath(3) – resolveuje všetky symlinky.
    public static func canonical(_ url: URL) -> URL {
        let path = url.path
        guard !path.isEmpty else { return url }
        if let resolved = resolveExisting(path) {
            return URL(fileURLWithPath: resolved, isDirectory: url.hasDirectoryPath)
        }
        // Neexistujúci cieľ: resolve parent + pripoj posledný komponent.
        let lastComponent = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        guard let resolvedParent = resolveExisting(parent.path) else { return url }
        var standardized = resolvedParent
        if !standardized.hasSuffix("/") { standardized += "/" }
        return URL(fileURLWithPath: standardized + lastComponent)
    }

    private static func resolveExisting(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return nil }
        let resolved = String(cString: buffer)
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory),
           isDirectory.boolValue, !path.hasSuffix("/"), !resolved.hasSuffix("/") {
            return resolved
        }
        return resolved
    }
}
