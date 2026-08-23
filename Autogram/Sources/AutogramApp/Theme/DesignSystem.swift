import SwiftUI
import AutogramKit

public extension View {
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func floatingGlass(cornerRadius: CGFloat = 24) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}

struct StatChip: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint.gradient)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct ConfidenceBar: View {
    let confidence: Double

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 44, height: 5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill((confidence > 0.75 ? Color.green : confidence > 0.5 ? Color.orange : Color.red).gradient)
                    .frame(width: max(confidence, 0.05) * 44, height: 5)
            }
            .help("Istota detekcie \(Int(confidence * 100)) %")
    }
}

struct ElementKindColor {
    static func color(for kind: SecurityElement.Kind) -> Color {
        switch kind {
        case .officialStamp: return .blue
        case .handwrittenSignature: return .green
        case .embossedSeal: return .orange
        case .initial: return .purple
        case .other: return .gray
        }
    }
}

struct StepperPill: View {
    let index: Int
    let title: String
    let symbol: String
    let state: StepState

    enum StepState { case pending, active, complete }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(fillGradient)
                    .frame(width: 28, height: 28)
                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state == .active ? .white : .secondary)
                }
            }
            Text(title)
                .font(.callout.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .pending ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if state == .active {
                Capsule().fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.45)))
            }
        }
    }

    private var fillGradient: AnyShapeStyle {
        switch state {
        case .complete: return AnyShapeStyle(Color.green.gradient)
        case .active: return AnyShapeStyle(Color.accentColor.gradient)
        case .pending: return AnyShapeStyle(Color.secondary.opacity(0.18))
        }
    }
}
