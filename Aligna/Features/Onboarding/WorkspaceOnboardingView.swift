import SwiftUI

struct WorkspaceOnboardingView: View {
    let session: AppSession

    var body: some View {
        NavigationStack {
            WorkspaceListView(session: session, isOnboarding: true)
                .safeAreaInset(edge: .bottom) {
                    Text(
                        "Create a workspace or accept an invitation to continue."
                    )
                    .font(.footnote)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
        }
    }
}
