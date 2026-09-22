import SwiftUI
import Chevron7Kit

struct SecurityElementKindOptions: View {
    let select: (SecurityElement.Kind) -> Void
    var body: some View {
        ForEach(SecurityElement.Kind.Group.allCases) { group in
            Section(group.rawValue) {
                ForEach(SecurityElement.Kind.allCases.filter { $0.group == group }) { kind in
                    Button { select(kind) } label: { Label(kind.label, systemImage: kind.sfSymbol) }
                }
            }
        }
    }
}

struct PhysicalSecurityElementSheet: View {
    @Bindable var store: ZakoSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SecurityElement.Kind = .bindingCord
    @State private var description = ""
    @State private var location = ""
    @State private var outputPage = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prvok skontrolovaný na origináli").font(.title2.bold())
            Text("Zaznamenajte fyzickú kontrolu prvku na strane \(store.previewPageIndex + 1). Rámček v skene sa nevytvorí.")
                .foregroundStyle(.secondary)
            Menu { SecurityElementKindOptions { kind = $0 } } label: {
                Label(kind.label, systemImage: kind.sfSymbol)
            }
            TextField("Vecný opis prvku", text: $description, axis: .vertical).lineLimit(2...4)
            TextField("Umiestnenie na origináli, napr. ľavý okraj zväzku", text: $location)
            OutputSecurityPagePicker(pageCount: store.analysis.totalPages, selection: $outputPage)
            Text("Vyberte stranu, na ktorej je prvok zachytený v novom dokumente. Ak chýba, záznam môžete uložiť a pred autorizáciou doplniť sken.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Zrušiť") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Pridať na kontrolu") {
                    store.addPhysicalSecurityElement(kind: kind, pageIndex: store.previewPageIndex,
                        description: description, location: location,
                        newDocumentPageIndex: outputPage < 0 ? nil : outputPage)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 500)
    }
}

struct OutputSecurityPagePicker: View {
    let pageCount: Int
    @Binding var selection: Int
    var body: some View {
        Picker("Strana zachytenia v PDF", selection: $selection) {
            Text("Zatiaľ neurčená").tag(-1)
            ForEach(0..<max(pageCount, 0), id: \.self) { Text("Strana \($0 + 1)").tag($0) }
        }
    }
}

struct PhysicalSecurityElementInspector: View {
    @Bindable var store: ZakoSessionStore
    let element: SecurityElement
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Skontrolované na origináli", systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
            TextField("Umiestnenie na origináli", text: Binding(
                get: { element.originalLocation },
                set: { store.updatePhysicalElement(id: element.id, location: $0, newDocumentPageIndex: element.newDocumentPageIndex) }))
            OutputSecurityPagePicker(pageCount: store.analysis.totalPages, selection: Binding(
                get: { element.newDocumentPageIndex ?? -1 },
                set: { store.updatePhysicalElement(id: element.id, location: element.originalLocation, newDocumentPageIndex: $0 < 0 ? nil : $0) }))
            Text("Fyzická kontrola sa nepoužije ako obrazový tréningový príklad.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }
}
