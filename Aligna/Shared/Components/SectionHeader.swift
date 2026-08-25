import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AlignaSpacing.medium) {
            VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AlignaColors.label)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AlignaColors.secondaryLabel)
                }
            }

            Spacer(minLength: AlignaSpacing.small)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
                    .accessibilityHint("Shows more items in this section")
            }
        }
    }
}

#Preview {
    SectionHeader(
        title: "Recent meetings",
        subtitle: "Your latest team conversations",
        actionTitle: "See all",
        action: {}
    )
    .padding()
}
