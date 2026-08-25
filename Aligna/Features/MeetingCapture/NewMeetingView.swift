import SwiftUI

struct MeetingCaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var completedMeeting: Meeting?

    let library: MeetingLibrary
    let dependencies: MeetingCaptureDependencies
    let context: MeetingCreationContext?

    init(
        library: MeetingLibrary,
        context: MeetingCreationContext? = nil,
        dependencies: MeetingCaptureDependencies? = nil
    ) {
        self.library = library
        self.context = context
        self.dependencies = dependencies ?? .app(
            ownerUserID: context?.organizerUserID
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completedMeeting {
                    MeetingDetailView(
                        meeting: completedMeeting,
                        library: library,
                        dependencies: dependencies
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
                } else {
                    MeetingCaptureView(
                        configuration: .temporary(context: context),
                        dependencies: dependencies,
                        repository: library.repository,
                        onSaved: { meeting in
                            library.includeSavedMeeting(meeting)
                            library.retryProcessing(
                                meeting,
                                using: dependencies.processing
                            )
                            completedMeeting = meeting
                        },
                        onCancelled: {
                            dismiss()
                        }
                    )
                }
            }
        }
    }
}

extension NewMeetingConfiguration {
    static func temporary(
        context: MeetingCreationContext?,
        now: Date = .now
    ) -> NewMeetingConfiguration {
        NewMeetingConfiguration(
            title: "Meeting · \(now.formatted(date: .abbreviated, time: .shortened))",
            participantNames: [],
            localeIdentifier: Locale.current.identifier,
            workspace: context?.workspace,
            organizerUserID: context?.organizerUserID,
            selectedMembers: []
        )
    }
}
