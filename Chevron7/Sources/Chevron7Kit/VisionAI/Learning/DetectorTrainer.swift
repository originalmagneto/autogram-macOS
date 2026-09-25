// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public enum DetectorStagingError: Error, Equatable {
    case missingImage(String)
}

/// In-app object-detector training (phase 2 of the learned detector).
/// The CreateML call itself has no suite test (about 9 minutes fixed cost;
/// `vision-train` covers that path manually). Everything around it is pure
/// and tested: staging, the single-job guard, scoring, promotion and the
/// model registry.
public enum DetectorTrainer {
    /// Copies the train partition into a fresh folder CreateML accepts
    /// (images plus `annotations.json`). A missing image throws instead of
    /// silently shrinking the training set.
    public static func stageTrainDirectory(dataset: URL, trainImages: [String],
                                           trainAnnotations: [CreateMLImageAnnotation],
                                           to staged: URL) throws {
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        for name in trainImages {
            let source = dataset.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw DetectorStagingError.missingImage(name)
            }
            try FileManager.default.copyItem(at: source, to: staged.appendingPathComponent(name))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(VisionTrainSplit.annotations(for: trainImages, from: trainAnnotations))
            .write(to: staged.appendingPathComponent("annotations.json"), options: .atomic)
    }
}
