import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AlignaSpacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AlignaColors.accent)
                .frame(width: 68, height: 68)
                .background(AlignaColors.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: AlignaSpacing.small) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
                    .accessibilityHint("Activates the next step")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AlignaSpacing.large)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    EmptyStateView(
        symbol: "waveform.badge.plus",
        title: "No meetings yet",
        message: "Record or upload a meeting when your team is ready.",
        actionTitle: "New meeting",
        action: {}
    )
    .padding()
}
