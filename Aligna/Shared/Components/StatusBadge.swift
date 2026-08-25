import SwiftUI

struct StatusBadge: View {
    enum Tone {
        case accent
        case success
        case warning
        case danger
        case neutral

        var foreground: Color {
            switch self {
            case .accent: AlignaColors.accent
            case .success: AlignaColors.success
            case .warning: AlignaColors.warning
            case .danger: AlignaColors.danger
            case .neutral: AlignaColors.secondaryLabel
            }
        }
    }

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let title: String
    var systemImage: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: AlignaSpacing.extraSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, AlignaSpacing.compact)
        .padding(.vertical, 6)
        .background(
            tone.foreground.opacity(colorSchemeContrast == .increased ? 0.2 : 0.11),
            in: Capsule()
        )
        .overlay {
            if colorSchemeContrast == .increased {
                Capsule()
                    .stroke(tone.foreground.opacity(0.7), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

#Preview("Status badges") {
    VStack(spacing: AlignaSpacing.medium) {
        StatusBadge(title: "Awaiting review", systemImage: "sparkles", tone: .warning)
        StatusBadge(title: "Complete", systemImage: "checkmark", tone: .success)
    }
    .padding()
}
