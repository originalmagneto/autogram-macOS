// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import SwiftUI
import UserNotifications
import Chevron7Kit

enum DetectorTrainingWindow {
    static let id = "detector-training"
}

/// The only way a training run starts: the reviewer opens it, sees the
/// report and the estimate, and presses the button. Training runs in a
/// `.utility` task, one job at a time, never in `--web-signing` mode.
@MainActor
@Observable
final class DetectorTrainingFlow {
    enum Step { case report, estimate, progress, result }

    let settingsStore: AppSettingsStore
    var step = Step.report
    var report: DetectorTrainingReadiness?
    var estimateText = ""
    var progressFraction = 0.0
    var phaseText = ""
    var resultText = ""
    var resultPromotable = false
    var errorText: String?
    var showBatteryConfirm = false
    var finishedWhileAway = false

    private let job = DetectorTrainingJob()
    private var runTask: Task<Void, Never>?
    private var pendingCandidate: TrainedCandidate?
    private var pendingGain: (recall: Double, precision: Double)?

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    var bank: ExampleBank { settingsStore.exampleBank }
    var modelsRoot: URL {
        get async {
            ModelRegistry.modelsDirectory(in: await bank.directory)
        }
    }

    func loadReport() async {
        do {
            let pages = try await bank.reviewedPages()
            let state = try TrainingState.load(from: await modelsRoot)
            let settings = settingsStore.settings
            report = DetectorTrainingReadiness.report(
                pages: pages, lastRunAt: state.lastRunAt,
                learnOn: settings.learnFromReviews,
                offersEnabled: settings.detectorTrainingOffersEnabled,
                snoozedUntil: state.snoozedUntil)
            let eligible = report?.reviewedPages ?? 0
            estimateText = DetectorTrainingEstimate.slovak(
                pages: eligible, secondsPerPage: state.secondsPerPage)
        } catch {
            errorText = "Správu sa nepodarilo načítať: \(error.localizedDescription)"
        }
    }

    func startTraining() {
        guard AppLaunchMode.current == .normal else {
            errorText = "Trénovanie nie je dostupné v režime podpisovania z prehliadača."
            return
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            showBatteryConfirm = true
            return
        }
        beginRun()
    }

    func beginRun() {
        step = .progress
        progressFraction = 0
        phaseText = "Príprava dát…"
        errorText = nil
        runTask = Task(priority: .utility) { await self.run() }
    }

    func cancelRun() {
        runTask?.cancel()
    }

    private func run() async {
        do {
            let candidate = try await job.run {
                try await DetectorTrainer.trainProduction(
                    bank: self.bank,
                    onProgress: { [weak self] fraction in
                        Task { @MainActor in
                            self?.progressFraction = fraction
                            self?.phaseText = "Trénovanie…"
                        }
                    })
            }
            phaseText = "Overenie na dokumentoch, ktoré model nevidel…"
            let (candidateMetrics, activeMetrics, labels) = try await score(candidate: candidate)
            let decision = DetectorPromotion.decide(candidate: candidateMetrics,
                                                    active: activeMetrics,
                                                    trainedLabels: labels)
            switch decision {
            case .promote(let gain, let delta):
                pendingCandidate = candidate
                pendingGain = (gain, delta)
                resultText = Self.resultLine(newMetrics: candidateMetrics, oldMetrics: activeMetrics,
                                             labels: labels)
                resultPromotable = true
            case .keep(let reason):
                try? FileManager.default.removeItem(
                    at: candidate.modelURL.deletingLastPathComponent())
                resultText = "Pôvodný detektor zostáva. Dôvod: \(reason)"
                resultPromotable = false
            }
            let state = try TrainingState.load(from: await modelsRoot)
            try TrainingState.save(TrainingState(
                lastRunAt: Date(), secondsPerPage: candidate.secondsPerPage,
                snoozedUntil: state.snoozedUntil), in: await modelsRoot)
            step = .result
        } catch is CancellationError {
            resultText = "Trénovanie ste zrušili. Nič sa nestratilo, dáta ostávajú."
            resultPromotable = false
            step = .result
        } catch let trainingError as DetectorTrainingError {
            switch trainingError {
            case .thermalRefused:
                errorText = "Mac je teraz príliš zahriaty. Počkajte na vychladnutie a skúste znova."
            case .thermalCancelled:
                errorText = "Mac sa počas trénovania kriticky zahrial, beh som zrušil. Po vychladnutí spustite znova."
            case .busy:
                errorText = "Trénovanie už beží."
            case .emptyTrainPartition:
                errorText = "V trénovacej sade nie sú žiadne strany."
            }
            step = .report
        } catch {
            errorText = "Trénovanie zlyhalo: \(error.localizedDescription)"
            step = .report
        }
        finishedWhileAway = true
    }

    func confirmUseNewDetector() {
        Task {
            do {
                guard let candidate = pendingCandidate, let gain = pendingGain else { return }
                let registry = ModelRegistry(root: await modelsRoot)
                _ = try registry.promote(candidate: candidate,
                                         recallGain: gain.recall, precisionDelta: gain.precision)
                pendingCandidate = nil
                resultText = "Nový detektor je aktívny. Predchádzajúci ostáva na jedno vrátenie v Nastaveniach."
                resultPromotable = false
            } catch {
                errorText = "Nový detektor sa nepodarilo aktivovať: \(error.localizedDescription)"
            }
        }
    }

    func keepOldDetector() {
        if let candidate = pendingCandidate {
            try? FileManager.default.removeItem(at: candidate.modelURL.deletingLastPathComponent())
            pendingCandidate = nil
        }
        resultText = "Ponechali ste pôvodný detektor."
        resultPromotable = false
    }

    func notifyIfAway(scenePhase: ScenePhase) {
        guard finishedWhileAway else { return }
        finishedWhileAway = false
        guard scenePhase != .active else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Trénovanie detektora dokončené"
            content.body = "Výsledok nájdete v okne trénovania."
            let request = UNNotificationRequest(identifier: "detector-training-done",
                                                content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    private func score(candidate: TrainedCandidate) async throws
        -> ([String: LabelMetrics], [String: LabelMetrics], Set<String>) {
        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("detector-score-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }
        let datasetURL = try await CreateMLExporter.export(bank: bank, to: exportRoot)
        let folder = datasetURL.deletingLastPathComponent()
        let truth = try JSONDecoder().decode([CreateMLImageAnnotation].self,
                                             from: Data(contentsOf: datasetURL))
        let splits = try JSONDecoder().decode([CreateMLDocumentSplit].self,
                                              from: Data(contentsOf: folder.appendingPathComponent("splits.json")))
        let vnModel = try LearnedModelLoader.load(at: candidate.compiledURL)
        let predictor = LearnedCandidateSource.coreMLPredictor(model: vnModel)
        var candidateMetrics: [String: LabelMetrics] = [:]
        for partition in ["validation", "test"] {
            let names = VisionTrainSplit.images(in: partition, splits: splits)
            let score = try await LearnedModelScorer.score(predict: predictor, imageNames: names,
                                                           folder: folder, truth: truth)
            for (label, m) in score.perLabel {
                let prev = candidateMetrics[label] ?? LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0)
                candidateMetrics[label] = LabelMetrics(
                    truePositives: prev.truePositives + m.truePositives,
                    falsePositives: prev.falsePositives + m.falsePositives,
                    falseNegatives: prev.falseNegatives + m.falseNegatives)
            }
        }
        var activeMetrics: [String: LabelMetrics] = [:]
        let registry = ModelRegistry(root: await modelsRoot)
        if (try? registry.activeModelID()) != nil,
           let activeModel = try? LearnedModelLoader.load(at: registry.activeCompiledURL()) {
            let activePredictor = LearnedCandidateSource.coreMLPredictor(model: activeModel)
            for partition in ["validation", "test"] {
                let names = VisionTrainSplit.images(in: partition, splits: splits)
                let score = try await LearnedModelScorer.score(predict: activePredictor, imageNames: names,
                                                               folder: folder, truth: truth)
                for (label, m) in score.perLabel {
                    let prev = activeMetrics[label] ?? LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0)
                    activeMetrics[label] = LabelMetrics(
                        truePositives: prev.truePositives + m.truePositives,
                        falsePositives: prev.falsePositives + m.falsePositives,
                        falseNegatives: prev.falseNegatives + m.falseNegatives)
                }
            }
        }
        return (candidateMetrics, activeMetrics, Set(report?.trainedLabels ?? []))
    }

    static func resultLine(newMetrics: [String: LabelMetrics], oldMetrics: [String: LabelMetrics],
                           labels: Set<String>) -> String {
        func mean(_ metrics: [String: LabelMetrics], _ pick: (LabelMetrics) -> Double) -> Double {
            guard !labels.isEmpty else { return 0 }
            return labels.map { pick(metrics[$0] ?? LabelMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0)) }
                .reduce(0, +) / Double(labels.count)
        }
        let newRecall = Int((mean(newMetrics, \.recall) * 100).rounded())
        let oldRecall = Int((mean(oldMetrics, \.recall) * 100).rounded())
        return "Nový detektor našiel \(newRecall) % prvkov, doterajší \(oldRecall) %."
    }
}

struct DetectorTrainingView: View {
    @Bindable var settingsStore: AppSettingsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var flow: DetectorTrainingFlow?

    var body: some View {
        Group {
            if let flow {
                content(flow: flow)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { flow = DetectorTrainingFlow(settingsStore: settingsStore) }
        .task { await flow?.loadReport() }
        .onChange(of: scenePhase) { _, phase in flow?.notifyIfAway(scenePhase: phase) }
    }

    @ViewBuilder
    private func content(flow: DetectorTrainingFlow) -> some View {
        @Bindable var flow = flow
        VStack(alignment: .leading, spacing: 16) {
            Text("Trénovanie vlastného detektora").font(.title2)
            if let message = flow.errorText {
                Text(message).foregroundStyle(.red)
            }
            switch flow.step {
            case .report: reportStep(flow: flow)
            case .estimate: estimateStep(flow: flow)
            case .progress: progressStep(flow: flow)
            case .result: resultStep(flow: flow)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func reportStep(flow: DetectorTrainingFlow) -> some View {
        @Bindable var flow = flow
        if let report = flow.report {
            Text("Detektor sa učí z vašich skontrolovaných strán, iba na tomto Macu. Nič nikam neposiela a nové návrhy bude stále potvrdzovať človek.")
            Text("Skontrolované strany: \(report.reviewedPages), dokumenty: \(report.documents).")
                .font(.headline)
            ForEach(report.trainedLabels.sorted(), id: \.self) { label in
                Text("\(label): \(report.boxesPerLabel[label] ?? 0) príkladov, trénuje sa.")
            }
            ForEach(report.leftOutLabels.keys.sorted(), id: \.self) { label in
                Text("\(label): \(report.leftOutLabels[label] ?? 0) príkladov, potrebných 15. Bez nich sa tento druh nenaučí.")
                    .foregroundStyle(.secondary)
            }
            if report.offerDue {
                Button("Pokračovať") { flow.step = .estimate }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Na prvé trénovanie treba \(DetectorTrainingReadiness.firstRunPages) skontrolovaných strán z \(DetectorTrainingReadiness.firstRunDocuments) dokumentov. Každá skontrolovaná strana vás k nemu priblíži.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView("Načítavam správu…")
        }
    }

    @ViewBuilder
    private func estimateStep(flow: DetectorTrainingFlow) -> some View {
        @Bindable var flow = flow
        Text("Odhad: \(flow.estimateText). Prvý odhad je hrubý, po prvom behu sa prepočíta z vášho Macu.")
        Text("Nechajte Mac na napájaní. Chevron7 môže ostať otvorený, konverzie môžu pokračovať. Zatvorenie aplikácie beh zruší a nič sa nestratí. Mac môže byť medzitým pomalší.")
            .foregroundStyle(.secondary)
        Button("Spustiť trénovanie") { flow.startTraining() }
            .buttonStyle(.borderedProminent)
            .alert("Mac beží v úspornom režime", isPresented: $flow.showBatteryConfirm) {
                Button("Spustiť aj tak") { flow.beginRun() }
                Button("Zrušiť", role: .cancel) {}
            } message: {
                Text("Trénovanie na batériu bude pomalšie. Odporúčame pripojiť napájanie.")
            }
    }

    @ViewBuilder
    private func progressStep(flow: DetectorTrainingFlow) -> some View {
        @Bindable var flow = flow
        Text(flow.phaseText).font(.headline)
        ProgressView(value: flow.progressFraction)
        Button("Zrušiť") { flow.cancelRun() }
    }

    @ViewBuilder
    private func resultStep(flow: DetectorTrainingFlow) -> some View {
        @Bindable var flow = flow
        Text(flow.resultText)
        if flow.resultPromotable {
            Button("Používať nový detektor") { flow.confirmUseNewDetector() }
                .buttonStyle(.borderedProminent)
            Button("Ponechať pôvodný") { flow.keepOldDetector() }
        }
    }
}

/// Quiet offer on ZaKo's Done screen after a conversion. Never interrupts:
/// it appears only when the readiness report says an offer is due.
struct DetectorTrainingOfferBanner: View {
    @Bindable var settingsStore: AppSettingsStore
    @Environment(\.openWindow) private var openWindow
    @State private var offerDue = false

    var body: some View {
        Group {
            if offerDue {
                HStack(spacing: 12) {
                    Text("Máte dosť skontrolovaných strán na natrénovanie vlastného detektora.")
                        .font(.callout)
                    Button("Pozrieť") {
                        offerDue = false
                        openWindow(id: DetectorTrainingWindow.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Neskôr") {
                        snooze()
                        offerDue = false
                    }
                    .controlSize(.small)
                    Button("Nepripomínať") {
                        settingsStore.settings.detectorTrainingOffersEnabled = false
                        offerDue = false
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .glassCard(cornerRadius: 10, padding: 0)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let bank = settingsStore.exampleBank
        guard let pages = try? await bank.reviewedPages() else { return }
        let bankDir = await bank.directory
        let root = ModelRegistry.modelsDirectory(in: bankDir)
        guard let state = try? TrainingState.load(from: root) else { return }
        let settings = settingsStore.settings
        offerDue = DetectorTrainingReadiness.report(
            pages: pages, lastRunAt: state.lastRunAt,
            learnOn: settings.learnFromReviews,
            offersEnabled: settings.detectorTrainingOffersEnabled,
            snoozedUntil: state.snoozedUntil).offerDue
    }

    private func snooze() {
        Task {
            let bank = settingsStore.exampleBank
            let root = ModelRegistry.modelsDirectory(in: await bank.directory)
            guard var state = try? TrainingState.load(from: root) else { return }
            state.snoozedUntil = Date().addingTimeInterval(7 * 24 * 3600)
            try? TrainingState.save(state, in: root)
        }
    }
}

/// Quiet line on the Done screen after a conversion with a newly reviewed
/// page: the reviewer sees the review feeding the training goal.
struct DetectorTrainingProgressLine: View {
    let store: ZakoSessionStore
    @State private var line: String?

    var body: some View {
        Group {
            if let line {
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        guard store.settingsStore.settings.learnFromReviews,
              !store.reviewedNonEmptyPages.isEmpty else { return }
        let bank = store.exampleBank
        guard let pages = try? await bank.reviewedPages() else { return }
        let root = ModelRegistry.modelsDirectory(in: await bank.directory)
        let state = (try? TrainingState.load(from: root)) ?? TrainingState()
        if let lastRun = state.lastRunAt {
            let fresh = pages.filter { $0.reviewedAt > lastRun }.count
            line = "Strana pribudla do učenia (\(fresh) nových z \(DetectorTrainingReadiness.retrainNewPages))."
        } else {
            line = "Strana pribudla do učenia (\(pages.count) z \(DetectorTrainingReadiness.firstRunPages))."
        }
    }
}
