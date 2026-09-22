import Foundation

/// How this process was started. The web bridge agent passes `--web-signing` when a
/// portal request finds Chevron7 not running; that launch shows only the signing panel.
enum AppLaunchMode: Equatable {
    case normal
    case webSigning

    static let argument = "--web-signing"

    static func from(arguments: [String]) -> AppLaunchMode {
        arguments.dropFirst().contains(argument) ? .webSigning : .normal
    }

    static let current = from(arguments: CommandLine.arguments)
}
