import SwiftUI
import AutogramKit
import AppKit

struct EvidenceDashboardView: View {
    @Bindable var settingsStore: AppSettingsStore
    @State private var records: [EvidenceRecord] = []
    @State private var filterText = ""
    @State private var statusFilter: EvidenceRecord.Status?
    @State private var selectedRecordID: UUID?
    @State private var isSubmitting = false
    @State private var submitFeedback: String?
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            filterBar
            Table(filteredRecords, selection: $selectedRecordID) {
                TableColumn("Evidenčné číslo") { record in
                    HStack(spacing: 6) {
                        if record.isOverdue { OverdueDot() }
                        Text(record.evidenceNumber ?? "—")
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                }
                .width(min: 130, ideal: 170)

                TableColumn("Stav") { record in
                    Label(record.status.rawValue, systemImage: record.status.sfSymbol)
                        .foregroundStyle(statusTint(record.status))
                }
                .width(min: 150, ideal: 190)

                TableColumn("Lehota CEZZK") { record in
                    deadlineLabel(record)
                }
                .width(min: 120, ideal: 160)

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
                .width(90)

                TableColumn("SHA-256") { record in
                    Text(String(record.fingerprintSHA256Hex.prefix(16)) + "…")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            reload()
            startClock()
        }
        .onDisappear { refreshTimer?.invalidate() }
        .sheet(isPresented: Binding(
            get: { detailRecord != nil },
            set: { if !$0 { selectedRecordID = nil } })) {
            if let record = detailRecord {
                RecordDetailView(settingsStore: settingsStore,
                                 record: binding(for: record),
                                 onClose: { selectedRecordID = nil })
            }
        }
    }

    private var detailRecord: EvidenceRecord? {
        guard let id = selectedRecordID else { return nil }
        return records.first { $0.id == id }
    }

    private func binding(for record: EvidenceRecord) -> Binding<EvidenceRecord> {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return .constant(record)
        }
        return Binding(get: { records[index] },
                       set: { records[index] = $0; persist($0) })
    }

    private func persist(_ record: EvidenceRecord) {
        settingsStore.evidenceStore.upsert(record)
    }

    private var summaryHeader: some View {
        let pending = records.filter(\.isSubmissionPending).count
        let overdue = records.filter(\.isOverdue).count
        let submitted = records.filter { $0.status == .submitted }.count
        return HStack(spacing: 12) {
            SummaryCard(title: "Konverzií celkovo", value: "\(records.count)", symbol: "archivebox", tint: .accentColor)
            SummaryCard(title: "Zapísaných v CEZZK", value: "\(submitted)", symbol: "checkmark.seal.fill", tint: .green)
            SummaryCard(title: "Čaká na odoslanie", value: "\(pending)", symbol: "tray.and.arrow.up", tint: pending > 0 ? .orange : .secondary)
            SummaryCard(title: "Po lehote 24 h", value: "\(overdue)", symbol: "clock.badge.exclamationmark", tint: overdue > 0 ? .red : .secondary)
            if let feedback = submitFeedback {
                Spacer()
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(feedback.hasPrefix("✓") ? Color.green : Color.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Hľadať podľa názvu alebo evidenčného čísla", text: $filterText)
                .textFieldStyle(.plain)

            ForEach([EvidenceRecord.Status?.none] + EvidenceRecord.Status.allCases.map { Optional($0) },
                    id: \.self) { status in
                chip(for: status)
            }

            Spacer()
            Button {
                submitPending()
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "tray.and.arrow.up")
                    }
                    Text("Odoslať čakajúce do CEZZK")
                }
            }
            .disabled(isSubmitting || !records.contains(where: \.isSubmissionPending))
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up.on.square")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .dividerBackground()
    }

    private func chip(for status: EvidenceRecord.Status?) -> some View {
        let title = status?.rawValue ?? "Všetky"
        let isActive = statusFilter == status || (status == nil && statusFilter == nil)
        return Button {
            statusFilter = status
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM. HH:mm"
        return formatter
    }()

    @ViewBuilder
    private func deadlineLabel(_ record: EvidenceRecord) -> some View {
        let formatter = Self.deadlineFormatter
        if record.status == .submitted {
            Text("zapísané ✓").font(.caption).foregroundStyle(.green)
        } else if record.isOverdue {
            Text("do \(formatter.string(from: record.submissionDeadline))")
                .font(.caption.weight(.semibold)).foregroundStyle(.red)
        } else if record.isSubmissionPending {
            Text("do \(formatter.string(from: record.submissionDeadline))")
                .font(.caption).foregroundStyle(.orange)
        } else {
            Text("do \(formatter.string(from: record.submissionDeadline))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filteredRecords: [EvidenceRecord] {
        var result = records
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        guard !filterText.isEmpty else { return result }
        let query = filterText.lowercased()
        return result.filter {
            $0.originalName.lowercased().contains(query) ||
            $0.newDocumentName.lowercased().contains(query) ||
            ($0.evidenceNumber ?? "").lowercased().contains(query)
        }
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
        records = settingsStore.evidenceStore.records
    }

    private func startClock() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in reload() }
        }
    }

    private func submitPending() {
        isSubmitting = true
        submitFeedback = nil
        reload()
        let pending = records.filter(\.isSubmissionPending)
        Task {
            var submittedCount = 0
            var failedCount = 0
            for record in pending {
                do {
                    try await settingsStore.ezzkService.submit(record.envelope())
                    var updated = record
                    updated.status = .submitted
                    updated.updatedAt = Date()
                    settingsStore.evidenceStore.upsert(updated)
                    submittedCount += 1
                } catch {
                    var updated = record
                    updated.status = .submissionFailed
                    updated.updatedAt = Date()
                    settingsStore.evidenceStore.upsert(updated)
                    failedCount += 1
                }
            }
            await MainActor.run {
                reload()
                isSubmitting = false
                submitFeedback = failedCount == 0
                    ? "✓ Odoslaných \(submittedCount) záznamov."
                    : "⚠ \(submittedCount) ok, \(failedCount) zamietnutých."
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "evidencia-konverzii.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? Data(settingsStore.evidenceStore.exportCSV().utf8).write(to: url, options: [.atomic])
        }
    }
}

struct OverdueDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.35 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .help("Záznam nepodlieha zápisu — lehota 24 h uplynula")
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct RecordDetailView: View {
    @Bindable var settingsStore: AppSettingsStore
    @Binding var record: EvidenceRecord
    let onClose: () -> Void
    @State private var copiedFingerprint = false

    private var timelineStages: [(String, Bool, Bool)] {
        [
            ("Evidenčné číslo", record.evidenceNumber != nil, false),
            ("Autorizácia KEP", record.status.progressIndex >= 3, false),
            ("Zápis v CEZZK", record.status == .submitted,
             record.status == .submissionFailed)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            StatusTimeline(stages: timelineStages)
            factsGrid
            attestationPreview
            HStack {
                if let uri = record.evidenceURI {
                    Link(destination: URL(string: "https://ezzk.iomo.sk")!) {
                        Label("Overiť v CEZZK", systemImage: "safari")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(uri, forType: .string)
                    } label: {
                        Image(systemName: "link.badge.plus")
                    }
                    .help("Skopírovať URI záznamu (\(uri))")
                }
                Spacer()
                Button(role: .destructive) {
                    settingsStore.evidenceStore.delete(id: record.id)
                    onClose()
                } label: {
                    Label("Zmazať z evidencie", systemImage: "trash")
                }
                Button("Zavrieť") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.originalName)
                .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                Label(record.status.rawValue, systemImage: record.status.sfSymbol)
                    .foregroundStyle(statusTint)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(LocalEvidenceStore.csvDate(record.conversionTime))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var factsGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 7) {
            row("Evidenčné číslo", record.evidenceNumber ?? "—")
            row("Osoba", record.performingPersonName.isEmpty ? "—" : record.performingPersonName)
            row("Nový dokument", record.newDocumentName)
            row("Strany / listy / prvky",
                "\(record.totalPages) / \(record.totalSheets) / \(record.securityElementCount)")
            fingerprintRow
        }
    }

    @ViewBuilder
    private var fingerprintRow: some View {
        let short = String(record.fingerprintSHA256Hex.prefix(24)) + "…"
        GridRow {
            Text("SHA-256")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(short)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.fingerprintSHA256Hex, forType: .string)
                    copiedFingerprint = true
                } label: {
                    Image(systemName: copiedFingerprint ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Skopírovať otlačok")
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private var attestationPreview: some View {
        GroupBox("Osvedčovacia doložka (XML)") {
            ScrollView {
                Text(record.attestationXML)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 180)
        }
    }

    private var statusTint: Color {
        switch record.status {
        case .draft, .awaitingNumber: return .secondary
        case .readyToSign: return .blue
        case .signed, .queuedForSubmission: return .orange
        case .submitted: return .green
        case .submissionFailed: return .red
        }
    }
}

struct StatusTimeline: View {
    let stages: [(label: String, done: Bool, failed: Bool)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                if index > 0 {
                    Rectangle()
                        .fill(stage.done ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(height: 2)
                }
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(stage.done ? Color.accentColor : Color.primary.opacity(0.06))
                            .strokeBorder(stage.done ? Color.clear : Color.primary.opacity(0.2), lineWidth: 1)
                            .frame(width: 22, height: 22)
                        Image(systemName: stage.failed ? "xmark" :
                                (stage.done ? "checkmark" : "circle"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(stage.done ? .white : .secondary)
                    }
                    Text(stage.label)
                        .font(.caption2)
                        .foregroundStyle(stage.done ? .primary : .secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private extension View {
    func dividerBackground() -> some View {
        shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}
