//
//  ContentView.swift
//  Aligna
//
//  Created by John Christopher Cruz on 7/27/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppAppearance.preferenceKey)
    private var storedAppearance = AppAppearance.system.rawValue
    @State private var session: AppSession

    init(
        bundle: Bundle = .main,
        processArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        #if DEBUG
        if processArguments.contains("-uiTestingVoiceSetup") {
            _session = State(
                initialValue: AppSession(
                    dependencies: .preview(),
                    initialState: .voiceSetup
                )
            )
            return
        }
        #endif

        switch SupabaseConfiguration.load(bundle: bundle) {
        case let .success(configuration):
            _session = State(
                initialValue: AppSession(
                    dependencies: .live(configuration: configuration)
                )
            )
        case let .failure(error):
            _session = State(
                initialValue: .configurationMissing(error)
            )
        }
    }

    var body: some View {
        sessionRoot
            .preferredColorScheme(
                AppAppearance.resolve(storedAppearance).preferredColorScheme
            )
            .animation(
                .easeInOut(duration: AlignaAnimation.appearance),
                value: storedAppearance
            )
            .task {
                await session.start()
            }
            .onOpenURL { url in
                Task { await session.handle(url: url) }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await session.refreshAuthenticationState() }
            }
            .sheet(isPresented: $session.isPresentingPasswordUpdate) {
                NewPasswordView(session: session)
            }
    }

    @ViewBuilder
    private var sessionRoot: some View {
        switch session.state {
        case .launching:
            ProgressView("Opening Aligna…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AlignaColors.background)
        case .configurationMissing:
            EmptyStateView(
                symbol: "wrench.and.screwdriver",
                title: "Aligna isn’t ready yet",
                message: "This build is missing its connection settings. Reinstall the app or contact support."
            )
            .padding(AlignaSpacing.large)
            .background(AlignaColors.background)
        case .signedOut:
            AuthenticationRootView(session: session)
        case .awaitingEmailVerification:
            CheckEmailView(session: session)
        case .profileIncomplete:
            ProfileOnboardingView(session: session)
        case .voiceSetup:
            VoiceSetupView(session: session)
        case .workspaceRequired:
            WorkspaceOnboardingView(session: session)
        case .authenticated:
            RootTabView(session: session)
                .id(session.currentWorkspace?.id)
        case let .failed(message):
            EmptyStateView(
                symbol: "exclamationmark.icloud",
                title: "Aligna needs attention",
                message: message,
                actionTitle: "Try again",
                action: {
                    Task { await session.refreshCollaboration() }
                }
            )
            .padding(AlignaSpacing.large)
            .background(AlignaColors.background)
        }
    }
}

#Preview {
    RootTabView(
        session: AppSession(
            dependencies: .preview(),
            initialState: .authenticated
        )
    )
}
