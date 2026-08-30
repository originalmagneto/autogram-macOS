import SwiftUI
import AutogramKit
import AppKit

struct EvidenceDashboardView: View {
    @Bindable var settingsStore: AppSettingsStore
    @State private var records: [EvidenceRecord] = []
    @State private var filterText = ""
    @State private var statusFilter: EvidenceRecord.Status?
    @State private var selectedRecordID: UUID?
    @State private var showDetail = false
    @State private var isSubmitting = false
    @State private var submitFeedback: String?
    @State private var refreshTimer: Timer?
    @State private var recordToDelete: EvidenceRecord?
    @State private var showDeleteConfirmation = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider().opacity(0.6)
            filterBar
            Divider().opacity(0.4)

            if records.isEmpty {
                ContentUnavailableView("Register je prázdny",
                                       systemImage: "archivebox",
                                       description: Text("Po dokončení prvej zaručenej konverzie sa tu zobrazí evidenčný záznam."))
            } else if filteredRecords.isEmpty && hasActiveFilter {
                ContentUnavailableView.search(text: filterText)
            } else {
                Table(filteredRecords, selection: $selectedRecordID) {
                    TableColumn("Evidenčné číslo") { record in
                        HStack(spacing: 6) {
                            if record.isOverdue { OverdueDot() }
                            Text(record.evidenceNumber ?? "nezískané")
                                .font(.callout.monospacedDigit().weight(.semibold))
                        }
                        .contextMenu { recordContextMenu(for: record) }
                    }
                    .width(min: 130, ideal: 170)

                    TableColumn("Stav") { record in
                        Label(UXLabels.evidenceStatusLabel(for: record.status, isOverdue: record.isOverdue),
                              systemImage: record.status.sfSymbol)
                            .foregroundStyle(statusTint(record.status))
                            .contextMenu { recordContextMenu(for: record) }
                    }
                    .width(min: 150, ideal: 190)

                    TableColumn("Lehota CEZZK") { record in
                        deadlineLabel(record)
                            .contextMenu { recordContextMenu(for: record) }
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("Dátum konverzie") { record in
                        Text(LocalEvidenceStore.csvDate(record.conversionTime))
                            .font(.caption.monospacedDigit())
                            .contextMenu { recordContextMenu(for: record) }
                    }
                    .width(min: 120, ideal: 140)

                    TableColumn("Pôvodný dokument") { record in
                        Text(record.originalName).lineLimit(1)
                            .help(record.originalName)
                            .contextMenu { recordContextMenu(for: record) }
                    }

                    TableColumn("Strany / Listy") { record in
                        Text("\(record.totalPages) / \(record.totalSheets)")
                            .font(.caption.monospacedDigit())
                            .contextMenu { recordContextMenu(for: record) }
                    }
                    .width(90)

                    TableColumn("SHA-256") { record in
                        Text(String(record.fingerprintSHA256Hex.prefix(16)) + "…")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .contextMenu { recordContextMenu(for: record) }
                    }
                }
                .onKeyPress(.return) {
                    guard selectedRecordID != nil else { return .ignored }
                    showDetail = true
                    return .handled
                }
                .onTapGesture(count: 2) {
                    if selectedRecordID != nil { showDetail = true }
                }
            }
        }
        .onAppear {
            reload()
            startClock()
        }
        .onDisappear { refreshTimer?.invalidate() }
        .sheet(isPresented: $showDetail) {
            if let record = detailRecord {
                RecordDetailView(settingsStore: settingsStore,
                                 record: binding(for: record),
                                 onClose: {
                                     showDetail = false
                                     selectedRecordID = nil
                                 })
            }
        }
        .confirmationDialog(
            "Naozaj chcete vymazať záznam z evidencie?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zmazať záznam", role: .destructive) {
                if let record = recordToDelete {
                    settingsStore.evidenceStore.delete(id: record.id)
                    reload()
                }
                recordToDelete = nil
            }
            Button("Zrušiť", role: .cancel) {
                recordToDelete = nil
            }
        } message: {
            Text("Tento krok je nevratný. Záznam bude odstránený z lokálneho registra konverzií.")
        }
    }

    @ViewBuilder
    private func recordContextMenu(for record: EvidenceRecord) -> some View {
        Button {
            selectedRecordID = record.id
            showDetail = true
        } label: {
            Label("Zobraziť detail a doložku", systemImage: "doc.text")
        }

        if let evidenceNumber = record.evidenceNumber {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(evidenceNumber, forType: .string)
            } label: {
                Label("Kopírovať evidenčné číslo", systemImage: "doc.on.doc")
            }
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.fingerprintSHA256Hex, forType: .string)
        } label: {
            Label("Kopírovať SHA-256 odtlačok", systemImage: "number.square")
        }

        Divider()

        Button(role: .destructive) {
            recordToDelete = record
            showDeleteConfirmation = true
        } label: {
            Label("Vymazať z evidencie…", systemImage: "trash")
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
            Spacer()
            if let feedback = submitFeedback {
                Text(feedback)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(feedback.hasPrefix("✓") ? Color.green : Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04), in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Hľadať podľa názvu alebo čísla", text: $filterText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .frame(minWidth: 180, idealWidth: 260, maxWidth: 320)

            Picker("Filtrovať podľa stavu", selection: $statusFilter) {
                Text("Všetky stavy").tag(EvidenceRecord.Status?.none)
                ForEach(EvidenceRecord.Status.allCases, id: \.self) { status in
                    Text(status.rawValue).tag(Optional(status))
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 150, idealWidth: 180, maxWidth: 220)

            Spacer(minLength: 8)
            Button {
                showDetail = true
            } label: {
                Label("Otvoriť detail", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .disabled(selectedRecordID == nil)
            .keyboardShortcut(.defaultAction)
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
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || !records.contains(where: \.isSubmissionPending))


            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up.on.square")
            }
            .buttonStyle(.bordered)
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Skúsiť znova", action: exportCSV)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
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
            Text(UXLabels.evidenceStatusLabel(for: record.status))
                .font(.caption)
                .foregroundStyle(.green)
        } else if record.isOverdue {
            Text("Po lehote — \(formatter.string(from: record.submissionDeadline))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if record.isSubmissionPending {
            Text("Blíži sa lehota — do \(formatter.string(from: record.submissionDeadline))")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text("Lehota: \(formatter.string(from: record.submissionDeadline))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hasActiveFilter: Bool {
        statusFilter != nil || !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let isDemoMode = settingsStore.ezzkSessionController.isDemoMode
        Task {
            var submittedCount = 0
            var failedCount = 0
            for record in pending {
                do {
                    try await settingsStore.ezzkService.submit(record.envelope())
                    if !isDemoMode {
                        var updated = record
                        updated.status = .submitted
                        updated.updatedAt = Date()
                        settingsStore.evidenceStore.upsert(updated)
                    }
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
                    ? (isDemoMode
                        ? "✓ Demo: lokálne pripravených \(submittedCount) záznamov."
                        : "✓ Odoslaných \(submittedCount) záznamov do CEZZK.")
                    : "⚠ \(submittedCount) úspešných, \(failedCount) zlyhalo."
            }
        }
    }


    private func exportCSV() {
        exportError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "evidencia-konverzii.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(settingsStore.evidenceStore.exportCSV().utf8).write(to: url, options: [.atomic])
            } catch {
                exportError = "Export sa nepodaril: \(error.localizedDescription)"
            }
        }
    }
}

struct OverdueDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .help("Záznam prekročil zákonnú lehotu 24 h na zápis do CEZZK")
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Record Detail Modal Sheet
struct RecordDetailView: View {
    @Bindable var settingsStore: AppSettingsStore
    @Binding var record: EvidenceRecord
    let onClose: () -> Void
    @State private var copiedFingerprint = false
    @State private var showDeleteConfirm = false
    @State private var selectedTab = 0

    private var timelineStages: [(String, Bool, Bool)] {
        [
            ("Evidenčné číslo", record.evidenceNumber != nil, false),
            ("Autorizácia KEP", record.status.progressIndex >= 3, false),
            ("Zápis v CEZZK", record.status == .submitted, record.status == .submissionFailed)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("Časť detailu záznamu", selection: $selectedTab) {
                Text("Prehľad záznamu").tag(0)
                Text("Osvedčovacia doložka (XML)").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                VStack(alignment: .leading, spacing: 14) {
                    StatusTimeline(stages: timelineStages)
                    factsGrid
                }
            } else {
                attestationPreview
            }

            Spacer()

            HStack {
                if let uri = record.evidenceURI {
                    Link(destination: URL(string: "https://ezzk.iomo.sk")!) {
                        Label("Overiť na portáli CEZZK", systemImage: "safari")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(uri, forType: .string)
                    } label: {
                        Image(systemName: "link.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skopírovať URI záznamu")
                    .help("Skopírovať URI záznamu (\(uri))")
                }

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Zmazať", systemImage: "trash")
                }

                Button("Zavrieť") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 320, idealWidth: 580, maxWidth: .infinity,
               minHeight: 400, idealHeight: 540, maxHeight: .infinity)
        .confirmationDialog("Naozaj chcete vymazať tento záznam?", isPresented: $showDeleteConfirm) {
            Button("Zmazať záznam", role: .destructive) {
                settingsStore.evidenceStore.delete(id: record.id)
                onClose()
            }
            Button("Zrušiť", role: .cancel) {}
        } message: {
            Text("Záznam bude natrvalo odstránený z lokálnej evidencie.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.originalName)
                .font(.title3.weight(.bold))
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
        Grid(horizontalSpacing: 16, verticalSpacing: 8) {
            row("Evidenčné číslo", record.evidenceNumber ?? "nezískané")
            row("Osvedčujúca osoba", record.performingPersonName.isEmpty ? "neurčená" : record.performingPersonName)
            row("Nový dokument", record.newDocumentName)
            row("Strany / listy / prvky",
                "\(record.totalPages) strán / \(record.totalSheets) listov / \(record.securityElementCount) prvkov")
            fingerprintRow
        }
        .glassCard(cornerRadius: 12, padding: 12)
    }

    @ViewBuilder
    private var fingerprintRow: some View {
        let short = String(record.fingerprintSHA256Hex.prefix(24)) + "…"
        GridRow {
            Text("SHA-256 odtlačok")
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
                .accessibilityLabel("Skopírovať SHA-256 odtlačok")
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
        GroupBox("Osvedčovacia doložka (XML dáta)") {
            ScrollView {
                Text(record.attestationXML)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 240)
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
