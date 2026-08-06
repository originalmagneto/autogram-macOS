import Observation

@MainActor @Observable
final class WorkspaceModel {
    private(set) var items: [PDFItem] = []

    func setItems(_ items: [PDFItem]) {
        self.items = items
    }

    func updateStatus(for fileID: String, to status: PDFItemStatus) {
        items = items.map { item in
            item.descriptor.id == fileID ? item.updatingStatus(to: status) : item
        }
    }
}
