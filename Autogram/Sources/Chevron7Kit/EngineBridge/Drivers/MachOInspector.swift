import Foundation

enum MachOArchitecture: String, Sendable, Hashable {
    case arm64
    case x86_64
}

protocol LipoProcess: Sendable {
    func architectures(at url: URL) throws -> Set<MachOArchitecture>
}

struct MachOInspector: Sendable {
    private let lipo: any LipoProcess

    init(lipo: any LipoProcess = SystemLipoProcess()) {
        self.lipo = lipo
    }

    func containsArm64Slice(at url: URL) throws -> Bool {
        try lipo.architectures(at: url).contains(.arm64)
    }
}

struct SystemLipoProcess: LipoProcess {
    func architectures(at url: URL) throws -> Set<MachOArchitecture> {
        let process = Process()
        let standardOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", url.path]
        process.standardOutput = standardOutput
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw DriverRequirementError.architectureInspectionFailed
        }
        guard process.terminationStatus == 0 else {
            throw DriverRequirementError.architectureInspectionFailed
        }

        let output = String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Set(output.split(whereSeparator: { $0.isWhitespace }).compactMap { MachOArchitecture(rawValue: String($0)) })
    }
}
