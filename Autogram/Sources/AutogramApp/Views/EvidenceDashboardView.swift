import SwiftUI
import AutogramKit
import AppKit

struct EvidenceDashboardView: View {
    let store: LocalEvidenceStore
    @State private var records: [EvidenceRecord] = []
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Table(filteredRecords) {
                TableColumn("Evidenčné číslo") { record in
                    Text(record.evidenceNumber ?? "—")
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                .width(min: 110, ideal: 130)

                TableColumn("Stav") { record in
                    Label(record.status.rawValue, systemImage: record.status.sfSymbol)
                        .foregroundStyle(statusTint(record.status))
                }
                .width(min: 150, ideal: 190)

                TableColumn("Dátum konverzie") { record in
                    Text(LocalEvidenceStore.csvDate(record.conversionTime))
                        .font(.caption.monospacedDigit())
                }
                .width(min: 120, ideal: 140)

                TableColumn("Pôvodný dokument") { record in
                    Text(record.originalName).lineLimit(1)
                        .help(record.originalName)
                }

                TableColumn("Strany / Listy") { record in
                    Text("\(record.totalPages) / \(record.totalSheets)")
                        .font(.caption.monospacedDigit())
                }
                .width(80)

                TableColumn("Prvky") { record in
                    Text("\(record.securityElementCount)")
                        .font(.caption.monospacedDigit())
                }
                .width(56)

                TableColumn("SHA-256") { record in
                    Text(String(record.fingerprintSHA256Hex.prefix(16)) + "…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { reload() }
    }

    private var filteredRecords: [EvidenceRecord] {
        guard !filterText.isEmpty else { return records }
        let query = filterText.lowercased()
        return records.filter {
            $0.originalName.lowercased().contains(query) ||
            $0.newDocumentName.lowercased().contains(query) ||
            ($0.evidenceNumber ?? "").lowercased().contains(query)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("Hľadať podľa názvu alebo evidenčného čísla", text: $filterText)
                .textFieldStyle(.plain)
            Spacer()
            Button {
                submitPending()
            } label: {
                Label("Odoslať čakajúce do CEZZK", systemImage: "tray.and.arrow.up")
            }
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up.on.square")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .dividerBackground()
    }

    private func statusTint(_ status: EvidenceRecord.Status) -> Color {
        switch status {
        case .draft, .awaitingNumber: return .secondary
        case .readyToSign: return .blue
        case .signed, .queuedForSubmission: return .orange
        case .submitted: return .green
        case .submissionFailed: return .red
        }
    }

    private func reload() {
        records = store.records
    }

    private func submitPending() {
        reload()
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "evidencia-konverzii.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? Data(store.exportCSV().utf8).write(to: url, options: [.atomic])
        }
    }
}

private extension View {
    func dividerBackground() -> some View {
        shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}
