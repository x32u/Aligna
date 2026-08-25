import SwiftUI

struct AuthenticationRootView: View {
    private enum Screen {
        case signIn
        case signUp
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AuthenticationViewModel()
    @State private var screen: Screen = .signIn
    @State private var showsRecovery = false
    @Namespace private var motionNamespace

    let session: AppSession

    var body: some View {
        NavigationStack {
            ZStack {
                switch screen {
                case .signIn:
                    SignInView(
                        session: session,
                        model: model,
                        motionNamespace: motionNamespace,
                        onCreateAccount: {
                            changeScreen(to: .signUp)
                        },
                        onForgotPassword: {
                            showsRecovery = true
                        }
                    )
                    .transition(authTransition)

                case .signUp:
                    SignUpView(
                        session: session,
                        model: model,
                        motionNamespace: motionNamespace,
                        onBackToSignIn: {
                            changeScreen(to: .signIn)
                        }
                    )
                    .transition(authTransition)
                }
            }
            .background(AlignaColors.background)
        }
        .tint(AlignaColors.accent)
        .sheet(isPresented: $showsRecovery) {
            NavigationStack {
                ForgotPasswordView(session: session, model: model)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var authTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity
            .combined(with: .scale(scale: 0.985))
            .combined(with: .offset(y: 14))
    }

    private func changeScreen(to newScreen: Screen) {
        withAnimation(
            reduceMotion
                ? .easeInOut(duration: AlignaAnimation.standard)
                : .spring(
                    duration: AlignaAnimation.deliberate,
                    bounce: 0.12
                )
        ) {
            screen = newScreen
        }
    }
}

#Preview("Authentication - Light") {
    AuthenticationRootView(
        session: AppSession(
            dependencies: .preview(user: nil, profile: nil, workspaces: []),
            initialState: .signedOut
        )
    )
}

#Preview("Authentication - Dark, Large Type") {
    AuthenticationRootView(
        session: AppSession(
            dependencies: .preview(user: nil, profile: nil, workspaces: []),
            initialState: .signedOut
        )
    )
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
