import SwiftUI

struct StatusPill: View {
    typealias Tone = StatusBadge.Tone

    let title: String
    var tone: Tone = .neutral

    var body: some View {
        StatusBadge(title: title, tone: tone)
    }
}
