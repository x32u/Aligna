import AVFAudio
import Observation
import SwiftUI

struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: MeetingAudioPlayer
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var speakerCorrectionMessage: String?
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionErrorMessage: String?

    let meeting: Meeting
    let library: MeetingLibrary?
    let dependencies: MeetingCaptureDependencies?

    init(
        meeting: Meeting,
        library: MeetingLibrary? = nil,
        dependencies: MeetingCaptureDependencies? = nil
    ) {
        self.meeting = meeting
        self.library = library
        self.dependencies = dependencies
        _player = State(
            initialValue: MeetingAudioPlayer(
                fileName: meeting.audioFileName
            )
        )
    }

    var body: some View {
        Group {
            if currentMeeting.processingStatus.isProcessing {
                processingView
            } else if currentMeeting.processingStatus == .failed {
                failureView
            } else {
                resultsView
            }
        }
        .background(AlignaColors.background)
        .navigationTitle(currentMeeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if library != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if currentMeeting.processingStatus == .complete {
                            Button {
                                editedTitle = currentMeeting.title
                                isEditingTitle = true
                            } label: {
                                Label("Edit Title", systemImage: "pencil")
                            }
                        }

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete Meeting", systemImage: "trash")
                        }
                        .disabled(isDeleting)
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .accessibilityLabel("Meeting actions")
                    .accessibilityHint("Edit or delete this meeting")
                    .disabled(isDeleting)
                }
            } else if currentMeeting.processingStatus == .complete {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        editedTitle = currentMeeting.title
                        isEditingTitle = true
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingTitle) {
            editTitleSheet
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Meeting", role: .destructive) {
                Task {
                    await deleteMeeting()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes the meeting, its notes, transcript, and saved recording."
            )
        }
        .alert(
            "Couldn’t Delete Meeting",
            isPresented: deletionErrorIsPresented
        ) {
            Button("OK") {
                deletionErrorMessage = nil
            }
        } message: {
            Text(
                deletionErrorMessage
                    ?? "Check your connection and try again."
            )
        }
        .onDisappear {
            player.stop()
        }
    }

    private var currentMeeting: Meeting {
        library?.meetings.first(where: { $0.id == meeting.id }) ?? meeting
    }

    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deletionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deletionErrorMessage = nil
                }
            }
        )
    }

    @MainActor
    private func deleteMeeting() async {
        guard !isDeleting, let library else { return }
        isDeleting = true
        player.stop()
        defer { isDeleting = false }

        do {
            try await library.delete(currentMeeting)
            dismiss()
        } catch {
            deletionErrorMessage =
                "Aligna kept the meeting and recording. Check your connection and try again."
        }
    }

    private var processingView: some View {
        ScrollView {
            VStack(spacing: AlignaSpacing.extraLarge) {
                Spacer(minLength: AlignaSpacing.large)

                ZStack {
                    Circle()
                        .fill(AlignaColors.brandCoral.opacity(0.12))
                        .frame(width: 84, height: 84)
                    Image(systemName: "waveform.and.sparkles")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(AlignaColors.brandCoral)
                }
                .accessibilityHidden(true)

                VStack(spacing: AlignaSpacing.small) {
                    Text(currentMeeting.processingStatus.customerTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AlignaColors.label)

                    Text("You can leave this screen. Aligna will keep working on your meeting.")
                        .font(.subheadline)
                        .foregroundStyle(AlignaColors.secondaryLabel)
                        .multilineTextAlignment(.center)
                }

                processingPhases

                if currentMeeting.processingStatus == .queued {
                    VStack(spacing: AlignaSpacing.small) {
                        Label(
                            queuedMessage,
                            systemImage: queuedSymbol
                        )
                        .font(.footnote)
                        .foregroundStyle(AlignaColors.secondaryLabel)
                        .multilineTextAlignment(.center)

                        if let library, let dependencies {
                            Button("Try now") {
                                library.retryProcessing(
                                    currentMeeting,
                                    using: dependencies.processing
                                )
                            }
                            .buttonStyle(.bordered)
                            .frame(
                                minHeight: AlignaSize.minimumTouchTarget
                            )
                        }
                    }
                    .padding(.horizontal, AlignaSpacing.medium)
                }

                localAudioSection
            }
            .padding(.horizontal, AlignaSpacing.large)
            .padding(.bottom, AlignaSpacing.extraLarge)
        }
    }

    private var processingPhases: some View {
        VStack(spacing: AlignaSpacing.zero) {
            phaseRow(
                title: "Preparing recording",
                phase: .preparingRecording
            )
            Divider().padding(.leading, 36)
            phaseRow(
                title: "Creating transcript",
                phase: .creatingTranscript
            )
            Divider().padding(.leading, 36)
            phaseRow(
                title: "Organizing your notes",
                phase: .organizingNotes
            )
        }
        .padding(AlignaSpacing.medium)
        .background(
            AlignaColors.elevatedSurface,
            in: RoundedRectangle(
                cornerRadius: AlignaRadius.large,
                style: .continuous
            )
        )
        .animation(
            .easeInOut(duration: AlignaAnimation.standard),
            value: currentMeeting.processingStatus
        )
    }

    private func phaseRow(
        title: String,
        phase: MeetingProcessingPhase
    ) -> some View {
        let currentPhase =
            currentMeeting.processingStatus.customerPhase
                ?? .preparingRecording
        let isComplete = currentPhase.rawValue > phase.rawValue
        let isCurrent = currentPhase == phase

        return HStack(spacing: AlignaSpacing.compact) {
            Group {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AlignaColors.success)
                } else if isCurrent {
                    ProcessingPhaseSpinner()
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(AlignaColors.tertiaryLabel)
                }
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(
                    isCurrent || isComplete
                        ? AlignaColors.label
                        : AlignaColors.secondaryLabel
                )
            Spacer()
        }
        .frame(minHeight: AlignaSize.minimumTouchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(isComplete ? "complete" : isCurrent ? "in progress" : "waiting")"
        )
    }

    private var failureView: some View {
        VStack(spacing: AlignaSpacing.large) {
            Spacer()

            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 46))
                .foregroundStyle(AlignaColors.warning)
                .accessibilityHidden(true)

            VStack(spacing: AlignaSpacing.small) {
                Text("We couldn’t finish your notes")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AlignaColors.label)
                Text(
                    library?.processingIssue(for: currentMeeting.id)?.message
                        ?? "Your recording is still safe on this iPhone. Try processing it again."
                )
                    .font(.subheadline)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .multilineTextAlignment(.center)
            }

            if let library, let dependencies {
                Button {
                    library.retryProcessing(
                        currentMeeting,
                        using: dependencies.processing
                    )
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(AlignaColors.brandCoral)
            }

            localAudioSection
            Spacer()
        }
        .padding(AlignaSpacing.large)
    }

    private var queuedMessage: String {
        library?.processingIssue(for: currentMeeting.id)?.message
            ?? "Your recording is saved and waiting to begin processing."
    }

    private var queuedSymbol: String {
        library?.processingIssue(for: currentMeeting.id)?.systemImage
            ?? "clock"
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AlignaSpacing.section) {
                if let analysis = currentMeeting.analysis {
                    overviewSection(analysis)
                    actionItemsSection(analysis)
                    insightsSection(
                        title: "Decisions",
                        symbol: "checkmark.seal",
                        items: analysis.decisions
                    )
                    insightsSection(
                        title: "Key Points",
                        symbol: "list.bullet.rectangle",
                        items: analysis.keyPoints
                    )

                    if !analysis.openQuestions.isEmpty {
                        insightsSection(
                            title: "Open Questions",
                            symbol: "questionmark.bubble",
                            items: analysis.openQuestions
                        )
                    }

                    if !analysis.followUps.isEmpty {
                        insightsSection(
                            title: "Follow-ups",
                            symbol: "arrowshape.turn.up.right",
                            items: analysis.followUps
                        )
                    }
                } else {
                    EmptyStateView(
                        symbol: "doc.text.magnifyingglass",
                        title: "Notes aren’t available",
                        message: "The recording is safe. Retry processing to create meeting notes."
                    )
                }

                localAudioSection
                transcriptSection

                Text(
                    "Audio is uploaded privately only while Aligna creates these notes, then the temporary cloud copy is deleted. The original recording stays on this iPhone."
                )
                .font(.caption)
                .foregroundStyle(AlignaColors.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AlignaSpacing.medium)
            .padding(.vertical, AlignaSpacing.large)
        }
    }

    private func overviewSection(
        _ analysis: MeetingAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
            SectionHeader(title: "Overview")
            Text(analysis.summary)
                .font(.body)
                .foregroundStyle(AlignaColors.label)
                .fixedSize(horizontal: false, vertical: true)

            if !analysis.languagesDetected.isEmpty {
                Text(analysis.languagesDetected.joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AlignaColors.secondaryLabel)
            }
        }
    }

    @ViewBuilder
    private func actionItemsSection(
        _ analysis: MeetingAnalysis
    ) -> some View {
        if !analysis.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
                SectionHeader(
                    title: "Action Items",
                    subtitle: "\(analysis.actionItems.count) suggested"
                )

                VStack(spacing: AlignaSpacing.zero) {
                    ForEach(
                        Array(analysis.actionItems.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        VStack(
                            alignment: .leading,
                            spacing: AlignaSpacing.small
                        ) {
                            Text(item.task)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AlignaColors.label)

                            HStack(spacing: AlignaSpacing.medium) {
                                Label(
                                    item.assigneeDisplayName
                                        ?? item.assignee
                                        ?? "Unassigned",
                                    systemImage: "person"
                                )
                                Label(
                                    item.dueDate ?? "No deadline",
                                    systemImage: "calendar"
                                )
                            }
                            .font(.caption)
                            .foregroundStyle(AlignaColors.secondaryLabel)

                            evidenceButton(item.evidence)
                        }
                        .padding(AlignaSpacing.medium)

                        if index < analysis.actionItems.count - 1 {
                            Divider().padding(.leading, AlignaSpacing.medium)
                        }
                    }
                }
                .background(
                    AlignaColors.elevatedSurface,
                    in: RoundedRectangle(
                        cornerRadius: AlignaRadius.large,
                        style: .continuous
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func insightsSection(
        title: String,
        symbol: String,
        items: [MeetingInsight]
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
                SectionHeader(title: title)

                VStack(spacing: AlignaSpacing.zero) {
                    ForEach(Array(items.enumerated()), id: \.element.id) {
                        index, item in
                        HStack(alignment: .top, spacing: AlignaSpacing.compact) {
                            Image(systemName: symbol)
                                .foregroundStyle(AlignaColors.brandCoral)
                                .frame(width: 22)
                                .accessibilityHidden(true)

                            VStack(
                                alignment: .leading,
                                spacing: AlignaSpacing.small
                            ) {
                                Text(item.text)
                                    .font(.body)
                                    .foregroundStyle(AlignaColors.label)
                                evidenceButton(item.evidence)
                            }
                        }
                        .padding(AlignaSpacing.medium)

                        if index < items.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(
                    AlignaColors.elevatedSurface,
                    in: RoundedRectangle(
                        cornerRadius: AlignaRadius.large,
                        style: .continuous
                    )
                )
            }
        }
    }

    private func evidenceButton(
        _ evidence: MeetingEvidence
    ) -> some View {
        Button {
            player.seek(to: evidence.timestampSeconds)
        } label: {
            Label(
                evidence.timestampSeconds.transcriptTimestamp,
                systemImage: "quote.opening"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(AlignaColors.secondaryLabel)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Moves audio playback to the supporting moment")
    }

    private var localAudioSection: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
            SectionHeader(title: "Recording")

            VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
                HStack(spacing: AlignaSpacing.compact) {
                    Button {
                        Task {
                            await player.togglePlayback()
                        }
                    } label: {
                        Group {
                            if player.isPreparing {
                                ProgressView()
                                    .tint(AlignaColors.label)
                            } else {
                                Image(
                                    systemName:
                                        player.isPlaying
                                        ? "pause.fill"
                                        : "play.fill"
                                )
                            }
                        }
                        .frame(
                            width: AlignaSize.minimumTouchTarget,
                            height: AlignaSize.minimumTouchTarget
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AlignaColors.brandCoral)
                    .disabled(!player.isAvailable || player.isPreparing)
                    .accessibilityLabel(
                        player.isPlaying ? "Pause recording" : "Play recording"
                    )

                    VStack(
                        alignment: .leading,
                        spacing: AlignaSpacing.extraSmall
                    ) {
                        ProgressView(
                            value: player.currentTime,
                            total: max(player.duration, 1)
                        )
                        .tint(AlignaColors.brandCoral)

                        HStack {
                            Text(player.currentTime.transcriptTimestamp)
                            Spacer()
                            Text(player.duration.transcriptTimestamp)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AlignaColors.secondaryLabel)
                    }
                }

                if let playbackMessage = player.playbackMessage {
                    Label(
                        playbackMessage,
                        systemImage: "speaker.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(AlignaSpacing.medium)
            .background(
                AlignaColors.elevatedSurface,
                in: RoundedRectangle(
                    cornerRadius: AlignaRadius.large,
                    style: .continuous
                )
            )
        }
    }

    private var transcriptSection: some View {
        DisclosureGroup {
            if !currentMeeting.attributedTranscript.isEmpty {
                LazyVStack(
                    alignment: .leading,
                    spacing: AlignaSpacing.medium
                ) {
                    ForEach(currentMeeting.attributedTranscript) { turn in
                        VStack(
                            alignment: .leading,
                            spacing: AlignaSpacing.extraSmall
                        ) {
                            HStack(spacing: AlignaSpacing.small) {
                                speakerLabel(for: turn)

                                Button(turn.startSeconds.transcriptTimestamp) {
                                    player.seek(to: turn.startSeconds)
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(
                                    AlignaColors.secondaryLabel
                                )
                            }

                            Text(turn.text)
                                .font(.body)
                                .foregroundStyle(AlignaColors.label)
                        }
                    }

                    if let speakerCorrectionMessage {
                        Label(
                            speakerCorrectionMessage,
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(AlignaColors.danger)
                    }
                }
                .padding(.top, AlignaSpacing.medium)
            } else if currentMeeting.transcript.isEmpty {
                Text("No transcript is available yet.")
                    .font(.subheadline)
                    .foregroundStyle(AlignaColors.secondaryLabel)
                    .padding(.vertical, AlignaSpacing.small)
            } else {
                LazyVStack(
                    alignment: .leading,
                    spacing: AlignaSpacing.medium
                ) {
                    ForEach(currentMeeting.transcript) { segment in
                        VStack(
                            alignment: .leading,
                            spacing: AlignaSpacing.extraSmall
                        ) {
                            if let start = segment.startTime {
                                Button(start.transcriptTimestamp) {
                                    player.seek(to: start)
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AlignaColors.brandCoral)
                            }
                            Text(segment.text)
                                .font(.body)
                                .foregroundStyle(AlignaColors.label)
                        }
                    }
                }
                .padding(.top, AlignaSpacing.medium)
            }
        } label: {
            SectionHeader(
                title: "Transcript",
                subtitle: transcriptSectionSubtitle
            )
        }
        .tint(AlignaColors.label)
    }

    private var transcriptSectionSubtitle: String? {
        if !currentMeeting.attributedTranscript.isEmpty {
            return "\(currentMeeting.attributedTranscript.count) speaker turns"
        }
        return currentMeeting.transcript.isEmpty
            ? nil
            : "\(currentMeeting.transcript.count) sections"
    }

    @ViewBuilder
    private func speakerLabel(
        for turn: AttributedTranscriptTurn
    ) -> some View {
        if eligibleParticipants.isEmpty
            || library == nil
            || dependencies == nil {
            Text(turn.speakerDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AlignaColors.brandCoral)
        } else {
            Menu {
                ForEach(eligibleParticipants) { participant in
                    if let userID = participant.userID {
                        Button(participant.name) {
                            correct(
                                turn: turn,
                                to: participant.name,
                                userID: userID
                            )
                        }
                    }
                }
            } label: {
                Label(
                    turn.speakerDisplayName,
                    systemImage: "chevron.down"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AlignaColors.brandCoral)
            }
            .accessibilityLabel(
                "\(turn.speakerDisplayName), change speaker"
            )
            .accessibilityHint(
                "Choose a participant to correct this speaker label"
            )
        }
    }

    private var eligibleParticipants: [TeamMember] {
        var result = currentMeeting.participants.filter {
            $0.userID != nil
        }
        if let owner = dependencies?.currentUser,
           owner.userID == currentMeeting.organizerUserID,
           !result.contains(where: { $0.userID == owner.userID }) {
            result.insert(owner, at: 0)
        }
        return result
    }

    private func correct(
        turn: AttributedTranscriptTurn,
        to displayName: String,
        userID: UUID
    ) {
        guard let library, let dependencies else { return }
        speakerCorrectionMessage = nil

        Task {
            do {
                try await dependencies.processing.correctSpeaker(
                    meetingID: currentMeeting.id,
                    stableSpeakerKey: turn.stableSpeakerKey,
                    participantUserID: userID
                )
                let corrected = currentMeeting.attributedTranscript.map {
                    existing in
                    guard existing.stableSpeakerKey
                            == turn.stableSpeakerKey else {
                        return existing
                    }
                    return AttributedTranscriptTurn(
                        id: existing.id,
                        stableSpeakerKey: existing.stableSpeakerKey,
                        speakerUserID: userID,
                        speakerDisplayName: displayName,
                        startSeconds: existing.startSeconds,
                        endSeconds: existing.endSeconds,
                        text: existing.text,
                        attributionConfidence: nil,
                        attributionSource: .manualCorrection
                    )
                }
                let updated = currentMeeting.withProcessing(
                    status: currentMeeting.processingStatus,
                    attributedTranscript: corrected
                )
                try await library.save(updated)
            } catch {
                speakerCorrectionMessage =
                    "That speaker couldn’t be updated. Please try again."
            }
        }
    }

    private var editTitleSheet: some View {
        NavigationStack {
            Form {
                Section("Meeting title") {
                    TextField("Title", text: $editedTitle)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Edit Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditingTitle = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEditedTitle()
                    }
                    .disabled(
                        editedTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private func saveEditedTitle() {
        let title = editedTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty, let library else {
            isEditingTitle = false
            return
        }
        let updated = currentMeeting.withProcessing(
            status: currentMeeting.processingStatus,
            title: title
        )
        Task { try? await library.save(updated) }
        isEditingTitle = false
    }
}

private struct ProcessingPhaseSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion
            )
        ) { context in
            let rotation = reduceMotion
                ? 0
                : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.1) / 1.1 * 360

            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(
                    AlignaColors.brandCoral,
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(rotation))
        }
        .padding(3)
        .accessibilityHidden(true)
    }
}

@MainActor
@Observable
private final class MeetingAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    private(set) var isPlaying = false
    private(set) var isPreparing = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackMessage: String?

    var isAvailable: Bool { player != nil }

    init(fileName: String?) {
        super.init()
        guard let fileName,
              let url = MeetingFileLocations.recordingURL(fileName: fileName),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            return
        }
        self.player = player
        player.delegate = self
        player.prepareToPlay()
        duration = player.duration
    }

    func togglePlayback() async {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            progressTask?.cancel()
            await MeetingPlaybackAudioSession.deactivate()
        } else {
            isPreparing = true
            playbackMessage = nil
            defer { isPreparing = false }

            do {
                try await MeetingPlaybackAudioSession.activate()
                if player.currentTime >= player.duration {
                    player.currentTime = 0
                    currentTime = 0
                }
                guard player.play() else {
                    playbackMessage =
                        "The recording couldn’t start playing. Please try again."
                    await MeetingPlaybackAudioSession.deactivate()
                    return
                }
                isPlaying = true
                startProgressUpdates()
            } catch {
                isPlaying = false
                playbackMessage =
                    "Audio output isn’t available right now. Check your volume or connected audio device and try again."
            }
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        progressTask?.cancel()
        progressTask = nil
        Task {
            await MeetingPlaybackAudioSession.deactivate()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    func audioPlayerDidFinishPlaying(
        _: AVAudioPlayer,
        successfully _: Bool
    ) {
        isPlaying = false
        currentTime = 0
        player?.currentTime = 0
        progressTask?.cancel()
        progressTask = nil
        Task {
            await MeetingPlaybackAudioSession.deactivate()
        }
    }

    func audioPlayerDecodeErrorDidOccur(
        _: AVAudioPlayer,
        error _: Error?
    ) {
        isPlaying = false
        playbackMessage =
            "This recording couldn’t be decoded, but the original file is still saved."
        progressTask?.cancel()
        progressTask = nil
        Task {
            await MeetingPlaybackAudioSession.deactivate()
        }
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                self.currentTime = self.player?.currentTime ?? 0
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
}

nonisolated private enum MeetingPlaybackAudioSession {
    static func activate() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio
            )
            try session.setActive(true)
        }.value
    }

    static func deactivate() async {
        await Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }.value
    }
}

#Preview("Processing") {
    NavigationStack {
        MeetingDetailView(
            meeting: Meeting(
                title: "Meeting · Today",
                projectName: "Aligna",
                scheduledAt: .now,
                durationSeconds: 180,
                status: .processing,
                processingStatus: .transcribing
            )
        )
    }
}
