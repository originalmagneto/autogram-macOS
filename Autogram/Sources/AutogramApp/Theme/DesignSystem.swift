import SwiftUI
import AutogramKit
import AppKit

public extension View {
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func liquidGlass(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.primary.opacity(0.06),
                                Color.primary.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    func floatingGlass(cornerRadius: CGFloat = 24) -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - Sticky Bottom Action Bar
struct StickyActionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.6)
            HStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}

// MARK: - Smartcard HUD Status
struct SmartcardHUDStatus: View {
    let isConnected: Bool
    let label: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isConnected ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                    .frame(width: 26, height: 26)
                Circle()
                    .fill(isConnected ? Color.green : Color.secondary)
                    .frame(width: 9, height: 9)
                    .shadow(color: isConnected ? Color.green.opacity(0.7) : Color.clear, radius: 4)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - eIDAS Verified Badge
struct EIDASBadge: View {
    enum Status {
        case qualified
        case warning
        case invalid
        case demo

        var label: String {
            switch self {
            case .qualified: return "eIDAS KEP"
            case .warning: return "Pozor (bez TSA)"
            case .invalid: return "Neplatný"
            case .demo: return "DEMO režim"
            }
        }

        var icon: String {
            switch self {
            case .qualified: return "checkmark.seal.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .invalid: return "xmark.seal.fill"
            case .demo: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .qualified: return .green
            case .warning: return .orange
            case .invalid: return .red
            case .demo: return .blue
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.caption2.weight(.bold))
            Text(status.label)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15), in: Capsule())
        .foregroundStyle(status.color)
        .overlay(
            Capsule()
                .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Flow Step Subheader Bar
struct FlowStepBar: View {
    let steps: [(title: String, symbol: String)]
    let currentStepIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isComplete = index < currentStepIndex
                let isActive = index == currentStepIndex

                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(stepFill(isComplete: isComplete, isActive: isActive))
                            .frame(width: 24, height: 24)
                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: step.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isActive ? .white : .secondary)
                        }
                    }
                    Text(step.title)
                        .font(.callout.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.primary : (isComplete ? Color.primary.opacity(0.8) : Color.secondary))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isActive {
                        Capsule()
                            .fill(.regularMaterial)
                            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
                    }
                }

                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private func stepFill(isComplete: Bool, isActive: Bool) -> AnyShapeStyle {
        if isComplete {
            return AnyShapeStyle(Color.green.gradient)
        } else if isActive {
            return AnyShapeStyle(Color.accentColor.gradient)
        } else {
            return AnyShapeStyle(Color.secondary.opacity(0.18))
        }
    }
}

// MARK: - Dropzone Artwork
struct DropzoneArtwork: View {
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(tint.opacity(0.08))
                .frame(width: 170, height: 170)
                .blur(radius: 20)

            // Outer ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.4), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 148, height: 148)

            // Inner glass bubble
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.15), radius: 12, y: 6)

            // Center Symbol
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(tint.gradient)
        }
    }
}

struct StatChip: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint.gradient)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
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
                    .frame(width: 26, height: 26)
                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
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
        .padding(.horizontal, 9)
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
