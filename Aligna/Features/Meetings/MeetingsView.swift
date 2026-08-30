import SwiftUI

struct MeetingsView: View {
    @State private var isPresentingNewMeeting = false
    @State private var pendingDeletion: Meeting?
    @State private var deletingMeetingIDs: Set<UUID> = []
    @State private var deletionErrorMessage: String?

    private let library: MeetingLibrary
    private let meetingContext: MeetingCreationContext?
    private let captureDependencies: MeetingCaptureDependencies

    init(
        library: MeetingLibrary? = nil,
        meetingContext: MeetingCreationContext? = nil,
        captureDependencies: MeetingCaptureDependencies? = nil
    ) {
        // No seeded sample meetings: an empty library must show the real empty
        // state rather than fabricated history.
        self.library = library ?? MeetingLibrary(
            repository: InMemoryMeetingRepository(),
            seedMeetings: []
        )
        self.meetingContext = meetingContext
        self.captureDependencies = captureDependencies ?? .app(
            ownerUserID: meetingContext?.organizerUserID
        )
    }

    var body: some View {
        Group {
            if library.meetings.isEmpty {
                EmptyStateView(
                    symbol: "waveform.badge.plus",
                    title: "No meetings yet",
                    message: "Record a meeting and Aligna will organize the transcript, decisions, and next steps.",
                    actionTitle: "New meeting",
                    action: { isPresentingNewMeeting = true }
                )
                .padding(AlignaSpacing.large)
            } else {
                List {
                    Section {
                        ForEach(library.meetings) { meeting in
                            NavigationLink(value: meeting) {
                                MeetingRow(meeting: meeting)
                            }
                            .disabled(deletingMeetingIDs.contains(meeting.id))
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: false
                            ) {
                                Button(role: .destructive) {
                                    pendingDeletion = meeting
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(
                                    deletingMeetingIDs.contains(meeting.id)
                                )
                            }
                        }
                    } header: {
                        Text("Your meetings")
                    } footer: {
                        Text(
                            "Original recordings stay on this iPhone. Temporary processing audio is private and removed after your notes are ready."
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AlignaColors.background)
        .navigationTitle("Meetings")
        .navigationDestination(for: Meeting.self) { meeting in
            MeetingDetailView(
                meeting: meeting,
                library: library,
                dependencies: captureDependencies
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNewMeeting = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create a new meeting")
            }
        }
        .sheet(isPresented: $isPresentingNewMeeting) {
            MeetingCaptureFlowView(
                library: library,
                context: meetingContext,
                dependencies: captureDependencies
            )
        }
        .confirmationDialog(
            "Delete this meeting?",
            isPresented: deletionConfirmationIsPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { meeting in
            Button("Delete Meeting", role: .destructive) {
                pendingDeletion = nil
                Task {
                    await deleteMeeting(meeting)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { meeting in
            Text(
                "“\(meeting.title)” and its saved recording will be permanently removed."
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
    }

    private var deletionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
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
    private func deleteMeeting(_ meeting: Meeting) async {
        guard deletingMeetingIDs.insert(meeting.id).inserted else { return }
        defer { deletingMeetingIDs.remove(meeting.id) }

        do {
            try await library.delete(meeting)
        } catch {
            deletionErrorMessage =
                "Aligna kept the meeting and recording. Check your connection and try again."
        }
    }
}

#Preview {
    NavigationStack {
        MeetingsView()
    }
}
