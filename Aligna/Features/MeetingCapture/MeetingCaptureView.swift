import SwiftUI

struct MeetingCaptureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var viewModel: MeetingCaptureViewModel
    @State private var isConfirmingCancellation = false

    let onCancelled: () -> Void

    init(
        configuration: NewMeetingConfiguration,
        dependencies: MeetingCaptureDependencies,
        repository: any MeetingRepository,
        onSaved: @escaping (Meeting) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: MeetingCaptureViewModel(
                configuration: configuration,
                dependencies: dependencies,
                repository: repository,
                onSaved: onSaved
            )
        )
        self.onCancelled = onCancelled
    }

    var body: some View {
        VStack(spacing: AlignaSpacing.extraLarge) {
            Spacer(minLength: AlignaSpacing.section)

            recordingStatus
            elapsedTime

            MicrophoneWaveformView(
                levels: viewModel.audioLevels,
                isPaused: viewModel.state == .paused,
                reduceMotion: reduceMotion
            )
            .frame(height: 92)
            .padding(.horizontal, AlignaSpacing.large)
            .accessibilityHidden(true)

            Spacer(minLength: AlignaSpacing.extraLarge)

            if case let .failed(error) = viewModel.state {
                errorView(error)
            } else {
                controls
            }
        }
        .padding(.horizontal, AlignaSpacing.large)
        .padding(.bottom, AlignaSpacing.large)
        .background(AlignaColors.background)
        .navigationTitle("Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isCaptureActive)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isCaptureActive {
                    Button("Cancel", role: .destructive) {
                        isConfirmingCancellation = true
                    }
                    .disabled(viewModel.state == .finishing)
                }
            }
        }
        .interactiveDismissDisabled(isCaptureActive)
        .confirmationDialog(
            "Discard this recording?",
            isPresented: $isConfirmingCancellation,
            titleVisibility: .visible
        ) {
            Button("Discard Recording", role: .destructive) {
                Task {
                    await viewModel.cancel()
                    onCancelled()
                }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("The unfinished recording will be removed from this iPhone.")
        }
        .task {
            if viewModel.state == .idle {
                await viewModel.start()
            }
        }
        .onDisappear {
            if isCaptureActive {
                Task { await viewModel.cancel() }
            }
        }
    }

    private var recordingStatus: some View {
        HStack(spacing: AlignaSpacing.small) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .opacity(viewModel.state == .recording ? 1 : 0.72)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.8).repeatForever(
                            autoreverses: true
                        ),
                    value: viewModel.state == .recording
                )

            Text(viewModel.stateTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AlignaColors.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meeting status: \(viewModel.stateTitle)")
    }

    private var elapsedTime: some View {
        Text(viewModel.formattedElapsedTime)
            .font(
                .system(.largeTitle, design: .rounded)
                    .weight(.semibold)
                    .monospacedDigit()
            )
            .foregroundStyle(AlignaColors.label)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .accessibilityLabel(
                "Elapsed meeting time \(viewModel.formattedElapsedTime)"
            )
    }

    private var controls: some View {
        HStack(spacing: AlignaSpacing.compact) {
            Button {
                Task {
                    if viewModel.state == .paused {
                        await viewModel.resume()
                    } else {
                        await viewModel.pause()
                    }
                }
            } label: {
                Label(
                    viewModel.state == .paused ? "Resume" : "Pause",
                    systemImage:
                        viewModel.state == .paused
                        ? "play.fill"
                        : "pause.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: AlignaSize.minimumTouchTarget)
            }
            .buttonStyle(.bordered)
            .tint(AlignaColors.secondaryLabel)
            .disabled(
                viewModel.state != .recording
                    && viewModel.state != .paused
            )

            Button {
                Task { await viewModel.finish() }
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AlignaSize.minimumTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(AlignaColors.brandCoral)
            .foregroundStyle(Color.black.opacity(0.78))
            .disabled(!viewModel.state.canFinish)
        }
    }

    private func errorView(_ error: MeetingCaptureError) -> some View {
        VStack(spacing: AlignaSpacing.medium) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AlignaColors.warning)

            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(AlignaColors.secondaryLabel)
                .multilineTextAlignment(.center)

            Button(error.recoveryTitle) {
                if error == .microphonePermissionDenied,
                   let settingsURL = URL(
                       string: UIApplication.openSettingsURLString
                   ) {
                    openURL(settingsURL)
                } else {
                    Task { await viewModel.retry() }
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: AlignaSize.minimumTouchTarget)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .recording:
            AlignaColors.brandCoral
        case .paused:
            AlignaColors.warning
        case .failed:
            AlignaColors.danger
        default:
            AlignaColors.accent
        }
    }

    private var isCaptureActive: Bool {
        switch viewModel.state {
        case .requestingPermission, .preparingModel, .ready,
             .recording, .paused, .finishing, .finalizingTranscript:
            true
        default:
            false
        }
    }
}

private struct MicrophoneWaveformView: View {
    let levels: [Float]
    let isPaused: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) {
                    _, level in
                    Capsule(style: .continuous)
                        .fill(
                            isPaused
                                ? AlignaColors.tertiaryLabel
                                : AlignaColors.brandCoral
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 2,
                            maxHeight: max(
                                2,
                                proxy.size.height
                                    * CGFloat(isPaused ? 0.05 : level)
                            )
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(
                reduceMotion
                    ? nil
                    : .smooth(duration: AlignaAnimation.quick),
                value: levels
            )
        }
    }
}

#Preview {
    NavigationStack {
        MeetingCaptureView(
            configuration: .temporary(context: nil),
            dependencies: .preview(),
            repository: InMemoryMeetingRepository(),
            onSaved: { _ in },
            onCancelled: {}
        )
    }
}
