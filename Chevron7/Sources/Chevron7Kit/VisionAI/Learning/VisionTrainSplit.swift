// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Pure helpers for splitting an exported detector dataset into train,
/// validation and test partitions. Shared by the vision-train spike and
/// (later) the in-app DetectorTrainer so the two cannot drift.
public enum VisionTrainSplit {
    public static func images(in partition: String, splits: [CreateMLDocumentSplit]) -> [String] {
        splits.filter { $0.partition == partition }.flatMap(\.images).sorted()
    }

    public static func annotations(for images: [String], from all: [CreateMLImageAnnotation]) -> [CreateMLImageAnnotation] {
        let wanted = Set(images)
        return all.filter { wanted.contains($0.image) }
    }

    /// Reverse of `SecurityElement.Kind.trainingLabel`. Prefers the canonical
    /// kind (one whose visual kind is itself); aliases such as
    /// `roundOfficialStamp` map to the same label but are not returned.
    public static func kind(forTrainingLabel label: String) -> SecurityElement.Kind? {
        let matches = SecurityElement.Kind.allCases.filter { $0.trainingLabel == label && $0.visualKind != nil }
        return matches.first { $0.visualKind == $0 } ?? matches.first
    }
}
