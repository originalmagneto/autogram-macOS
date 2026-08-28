import Foundation

/// Shared, testable wording for VoiceOver and other accessibility surfaces.
public enum UXLabels {
    public static func confidenceLabel(for confidence: Double) -> String {
        let percentage = Int((min(max(confidence, 0), 1) * 100).rounded())
        return "Istota \(percentage) %"
    }

    public static func provenanceLabel(detectedByAI: Bool) -> String {
        detectedByAI ? "AI detekcia" : "Pridané ručne"
    }

    public static func evidenceStatusLabel(for status: EvidenceRecord.Status,
                                           isOverdue: Bool = false) -> String {
        if isOverdue { return "Po lehote" }
        switch status {
        case .draft: return "Koncept"
        case .awaitingNumber: return "Čaká na evidenčné číslo"
        case .readyToSign: return "Pripravené na autorizáciu"
        case .signed: return "Stav: čaká na odoslanie"
        case .queuedForSubmission: return "Stav: čaká na odoslanie"
        case .submitted: return "Zapísané v CEZZK"
        case .submissionFailed: return "Odoslanie zlyhalo – čaká na opakovanie"
        }
    }
}
