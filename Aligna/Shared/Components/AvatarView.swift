import SwiftUI

struct AvatarView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let name: String
    var initials: String?
    var size: CGFloat = AlignaSize.avatarMedium

    var body: some View {
        Text(displayInitials)
            .font(avatarFont)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(colorSchemeContrast == .increased ? 0.22 : 0.13))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        tint.opacity(colorSchemeContrast == .increased ? 0.8 : 0.2),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 0.5
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }

    private var displayInitials: String {
        if let initials, !initials.isEmpty {
            return initials
        }

        return name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }

    private var avatarFont: Font {
        size <= AlignaSize.avatarSmall
            ? .caption2.weight(.bold)
            : .caption.weight(.bold)
    }

    private var tint: Color {
        let palette: [UIColor] = [
            .systemTeal,
            .systemOrange,
            .systemPink,
            .systemBrown,
            .systemMint
        ]
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(uiColor: palette[seed % palette.count])
    }
}

#Preview("Avatars") {
    HStack {
        AvatarView(name: "John Cruz")
        AvatarView(name: "Maya Chen")
        AvatarView(name: "Liam Rivera", size: AlignaSize.avatarSmall)
    }
    .padding()
}
