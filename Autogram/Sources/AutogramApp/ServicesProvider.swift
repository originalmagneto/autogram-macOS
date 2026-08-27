import AppKit

/// Routes files received from the Finder Quick Action (NSServices) into the signing flow.
@MainActor
final class FinderSigningRouter: @unchecked Sendable {
    static let shared = FinderSigningRouter()

    private var handler: (([URL]) -> Void)?
    private var pending: [[URL]] = []

    func enqueue(_ urls: [URL]) {
        if let handler {
            handler(urls)
        } else {
            pending.append(urls)
        }
    }

    /// Installs the real handler once RootView is ready; flushes queued requests.
    func install(_ handler: @escaping ([URL]) -> Void) {
        self.handler = handler
        let queued = pending
        pending.removeAll()
        queued.forEach(handler)
    }
}

/// NSServices provider: receives PDF file URLs selected in Finder.
@objc final class ServicesProvider: NSObject {
    @objc func signFiles(_ pasteboard: NSPasteboard,
                         userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else {
            error.pointee = "Nie sú vybrané žiadne PDF súbory." as NSString
            return
        }
        DispatchQueue.main.async {
            FinderSigningRouter.shared.enqueue(pdfs)
        }
    }
}
