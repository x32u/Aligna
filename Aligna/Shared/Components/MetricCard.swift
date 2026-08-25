import SwiftUI

struct MetricCard: View {
    let symbol: String
    let value: String
    let label: String
    var tint: Color = AlignaColors.accent

    var body: some View {
        AlignaCard(padding: AlignaSpacing.compact) {
            VStack(alignment: .leading, spacing: AlignaSpacing.small) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: AlignaSize.compactIcon, height: AlignaSize.compactIcon)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: AlignaRadius.small))
                    .accessibilityHidden(true)

                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AlignaColors.label)
                    .contentTransition(.numericText())

                Text(label)
                    .font(.caption)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}

#Preview("Metric light") {
    MetricCard(
        symbol: "sparkles",
        value: "2",
        label: "Pending AI reviews",
        tint: AlignaColors.warning
    )
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Metric dark") {
    MetricCard(
        symbol: "checklist",
        value: "7",
        label: "Open action items"
    )
    .padding()
    .preferredColorScheme(.dark)
}
