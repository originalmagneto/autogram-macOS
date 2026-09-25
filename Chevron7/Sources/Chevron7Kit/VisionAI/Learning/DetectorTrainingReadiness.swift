// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Whether the app owes the reviewer a training offer, and what the offer
/// would train on. Pure and tested; the app feeds it from the bank and the
/// training state stored next to it.
public struct DetectorTrainingReadiness: Sendable, Equatable {
    public var reviewedPages: Int
    public var documents: Int
    public var boxesPerLabel: [String: Int]
    public var trainedLabels: [String]
    public var leftOutLabels: [String: Int]
    public var newSinceLastTraining: Int
    public var offerDue: Bool

    public static let firstRunPages = 40
    public static let firstRunDocuments = 8
    public static let retrainNewPages = 20
    public static let boxesPerLabelMinimum = 15

    public static func report(pages: [ReviewedBankPage], lastRunAt: Date?,
                              learnOn: Bool, offersEnabled: Bool, snoozedUntil: Date?,
                              now: Date = Date()) -> DetectorTrainingReadiness {
        var boxesPerLabel: [String: Int] = [:]
        for box in pages.flatMap(\.boxes) {
            boxesPerLabel[box.kind.trainingLabel, default: 0] += 1
        }
        let trained = boxesPerLabel.filter { $0.value >= boxesPerLabelMinimum }.map(\.key).sorted()
        let leftOut = boxesPerLabel.filter { $0.value < boxesPerLabelMinimum }
        let fresh = lastRunAt.map { run in pages.filter { $0.reviewedAt > run }.count } ?? pages.count
        let gateMet: Bool
        if lastRunAt == nil {
            gateMet = pages.count >= firstRunPages
                && Set(pages.map(\.documentSHA256)).count >= firstRunDocuments
        } else {
            gateMet = fresh >= retrainNewPages
        }
        let snoozed = snoozedUntil.map { $0 > now } ?? false
        return DetectorTrainingReadiness(
            reviewedPages: pages.count,
            documents: Set(pages.map(\.documentSHA256)).count,
            boxesPerLabel: boxesPerLabel,
            trainedLabels: trained,
            leftOutLabels: leftOut,
            newSinceLastTraining: fresh,
            offerDue: learnOn && offersEnabled && !snoozed && gateMet)
    }
}

/// Run state the estimate and the offer logic need. Lives in
/// `<bank>/models/training-state.json`, so deleting the bank deletes it.
public struct TrainingState: Codable, Equatable, Sendable {
    public var lastRunAt: Date?
    public var secondsPerPage: Double?
    public var snoozedUntil: Date?

    public init(lastRunAt: Date? = nil, secondsPerPage: Double? = nil, snoozedUntil: Date? = nil) {
        self.lastRunAt = lastRunAt; self.secondsPerPage = secondsPerPage; self.snoozedUntil = snoozedUntil
    }

    public static func fileURL(in modelsDir: URL) -> URL {
        modelsDir.appendingPathComponent("training-state.json")
    }

    public static func load(from modelsDir: URL) throws -> TrainingState {
        let url = fileURL(in: modelsDir)
        guard FileManager.default.fileExists(atPath: url.path) else { return TrainingState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrainingState.self, from: Data(contentsOf: url))
    }

    public static func save(_ state: TrainingState, in modelsDir: URL) throws {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL(in: modelsDir), options: .atomic)
    }
}
