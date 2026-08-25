import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: AlignaSize.standardControlHeight)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(
            .roundedRectangle(radius: AlignaRadius.medium)
        )
        .accessibilityLabel(title)
    }
}

#Preview {
    PrimaryActionButton(
        title: "Start meeting",
        systemImage: "waveform",
        action: {}
    )
    .padding()
}
