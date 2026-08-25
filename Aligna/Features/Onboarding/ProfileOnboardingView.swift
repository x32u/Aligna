import SwiftUI

struct ProfileOnboardingView: View {
    let session: AppSession

    var body: some View {
        NavigationStack {
            ProfileEditorView(session: session, isOnboarding: true)
        }
    }
}
