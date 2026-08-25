import SwiftUI

struct VoiceSetupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: VoiceSetupViewModel
    @State private var orbPulse = false

    let session: AppSession
    let onFinished: (() -> Void)?

    init(
        session: AppSession,
        onFinished: (() -> Void)? = nil
    ) {
        self.session = session
        self.onFinished = onFinished
        _model = State(
            initialValue: VoiceSetupViewModel(
                displayName: session.profile?.displayName ?? "there",
                engine: session.dependencies.voiceEngine,
                profiles: session.dependencies.voiceProfiles
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .introduction:
                    introduction
                case .preparing:
                    preparation
                case .ready, .recording, .evaluating, .saving:
                    phraseFlow
                case .completed:
                    completion
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AlignaColors.background)
            .animation(
                reduceMotion ? nil : .easeInOut(
                    duration: AlignaAnimation.standard
                ),
                value: model.stage
            )
            .toolbar {
                if model.stage == .introduction, onFinished != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            onFinished?()
                        }
                    }
                } else if model.stage != .introduction
                    && model.stage != .completed
                    && model.canCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            model.resetToIntroduction()
                        }
                    }
                }
            }
        }
    }

    private var introduction: some View {
        ScrollView {
            VStack(spacing: AlignaSpacing.large) {
                Spacer(minLength: AlignaSpacing.extraLarge)
                AlignaBrandMarkView(size: 76)

                VStack(spacing: AlignaSpacing.compact) {
                    Text("Help Aligna recognize you")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AlignaColors.label)
                        .multilineTextAlignment(.center)
                    Text(
                        "Read four short lines in your normal voice. You’ll see one line at a time, and Aligna will continue automatically."
                    )
                    .font(.body)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Label(
                    "Your setup recordings stay on this iPhone and are deleted after your protected voice profile is created.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(AlignaColors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(AlignaSpacing.medium)
                .alignaCard()
                .accessibilityElement(children: .combine)

                if let message = model.message {
                    messageView(message)
                }

                VStack(spacing: AlignaSpacing.compact) {
                    Button {
                        Task { await model.begin() }
                    } label: {
                        Label(
                            "Set up my voice",
                            systemImage: "waveform"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AlignaSize.standardControlHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AlignaColors.primaryAction)
                    .foregroundStyle(AlignaColors.primaryActionText)

                    if onFinished == nil {
                        Button("Skip for now") {
                            Task {
                                await session.finishVoiceSetup(as: .skipped)
                                onFinished?()
                            }
                        }
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                        .foregroundStyle(AlignaColors.secondaryLabel)
                    }
                }
            }
            .padding(AlignaSpacing.large)
        }
    }

    private var preparation: some View {
        VStack(spacing: AlignaSpacing.large) {
            ProgressView()
                .controlSize(.large)
                .tint(AlignaColors.brandCoral)
            Text("Getting things ready")
                .font(.title2.bold())
                .foregroundStyle(AlignaColors.label)
            Text("This happens only the first time.")
                .foregroundStyle(AlignaColors.secondaryLabel)
        }
        .padding(AlignaSpacing.large)
    }

    private var phraseFlow: some View {
        ScrollView {
            VStack(spacing: AlignaSpacing.extraLarge) {
                VStack(spacing: AlignaSpacing.small) {
                    Text(
                        "Phrase \(model.phraseIndex + 1) of \(model.phrases.count)"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AlignaColors.secondaryLabel)

                    HStack(spacing: AlignaSpacing.small) {
                        ForEach(model.phrases.indices, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index <= model.phraseIndex
                                        ? AlignaColors.brandCoral
                                        : AlignaColors.border
                                )
                                .frame(height: 4)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Phrase \(model.phraseIndex + 1) of \(model.phrases.count)"
                    )
                }

                VStack(alignment: .leading, spacing: AlignaSpacing.small) {
                    Label("Read this aloud", systemImage: "quote.bubble")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AlignaColors.brandCoral)

                    Text(model.currentPhrase)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AlignaColors.label)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Say it naturally—you don’t need to match every word perfectly.")
                        .font(.footnote)
                        .foregroundStyle(AlignaColors.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AlignaSpacing.roomy)
                .alignaCard(padding: 0)
                .accessibilityElement(children: .combine)

                microphoneOrb

                statusText

                if let message = model.message {
                    messageView(message)
                }

                controls
            }
            .padding(AlignaSpacing.large)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var microphoneOrb: some View {
        ZStack {
            Circle()
                .fill(AlignaColors.brandCoral.opacity(0.12))
                .frame(width: 150, height: 150)
                .scaleEffect(
                    model.stage == .recording
                        ? 1 + CGFloat(model.microphoneLevel) * 0.22
                        : 1
                )
            Circle()
                .fill(AlignaColors.brandCoral)
                .frame(width: 92, height: 92)
                .shadow(
                    color: AlignaColors.brandCoral.opacity(0.22),
                    radius: 18,
                    y: 8
                )
            Image(
                systemName:
                    model.stage == .recording
                    ? "waveform"
                    : "mic.fill"
            )
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: model.stage == .recording && !reduceMotion
            )
        }
        .frame(height: 170)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.12),
            value: model.microphoneLevel
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            model.stage == .recording
                ? "Recording your voice"
                : "Microphone ready"
        )
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.stage {
        case .recording:
            Text("Read the line, then pause. Aligna will continue automatically.")
        case .evaluating:
            Text("Checking this line…")
        case .saving:
            Text("Protecting your voice profile…")
        default:
            Text("Find a quiet place and read the line in your normal voice.")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.stage {
        case .ready:
            Button {
                Task { await model.startPhrase() }
            } label: {
                Label(
                    model.isFailure ? "Try again" : "Start recording",
                    systemImage: "mic.fill"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AlignaSize.standardControlHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(AlignaColors.primaryAction)
            .foregroundStyle(AlignaColors.primaryActionText)
        case .recording:
            Button("Cancel recording") {
                model.cancelRecording()
            }
            .frame(minHeight: AlignaSize.minimumTouchTarget)
            .foregroundStyle(AlignaColors.secondaryLabel)
        case .evaluating, .saving:
            ProgressView()
                .controlSize(.large)
                .tint(AlignaColors.brandCoral)
        default:
            EmptyView()
        }
    }

    private var completion: some View {
        VStack(spacing: AlignaSpacing.large) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AlignaColors.success)
                .symbolEffect(
                    .bounce,
                    options: .nonRepeating,
                    value: model.stage == .completed && !reduceMotion
                )
                .accessibilityHidden(true)
            Text("Aligna knows your voice")
                .font(.largeTitle.bold())
                .foregroundStyle(AlignaColors.label)
                .multilineTextAlignment(.center)
            Text(
                "When you join a meeting, Aligna can use your protected voice profile to label your words."
            )
            .font(.body)
            .foregroundStyle(AlignaColors.secondaryLabel)
            .multilineTextAlignment(.center)

            Button("Continue") {
                Task {
                    await session.finishVoiceSetup(as: .enrolled)
                    onFinished?()
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AlignaSize.standardControlHeight)
            .buttonStyle(.borderedProminent)
            .tint(AlignaColors.primaryAction)
            .foregroundStyle(AlignaColors.primaryActionText)
        }
        .padding(AlignaSpacing.large)
    }

    private func messageView(_ message: String) -> some View {
        Label(
            message,
            systemImage: model.isFailure
                ? "exclamationmark.circle"
                : "info.circle"
        )
        .font(.footnote)
        .foregroundStyle(
            model.isFailure
                ? AlignaColors.danger
                : AlignaColors.secondaryLabel
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VoiceSetupView(
        session: AppSession(
            dependencies: .preview(),
            initialState: .voiceSetup
        )
    )
}
