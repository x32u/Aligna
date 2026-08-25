import SwiftUI

enum AlignaColors {
    static let accent = Color.accentColor
    static let brandCoral = Color(
        red: 1,
        green: 113 / 255,
        blue: 94 / 255
    )
    static let background = adaptive(
        light: UIColor(red: 0.969, green: 0.945, blue: 0.906, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.039, blue: 0.035, alpha: 1),
        increasedContrastLight: UIColor(
            red: 1,
            green: 0.976,
            blue: 0.937,
            alpha: 1
        ),
        increasedContrastDark: UIColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )
    )
    static let surface = adaptive(
        light: UIColor(red: 1, green: 0.976, blue: 0.941, alpha: 1),
        dark: UIColor(red: 0.106, green: 0.102, blue: 0.094, alpha: 1),
        increasedContrastLight: .white,
        increasedContrastDark: UIColor(
            red: 0.133,
            green: 0.125,
            blue: 0.114,
            alpha: 1
        )
    )
    static let elevatedSurface = adaptive(
        light: UIColor(red: 1, green: 0.992, blue: 0.973, alpha: 1),
        dark: UIColor(red: 0.137, green: 0.129, blue: 0.118, alpha: 1),
        increasedContrastLight: .white,
        increasedContrastDark: UIColor(
            red: 0.176,
            green: 0.165,
            blue: 0.149,
            alpha: 1
        )
    )
    static let label = adaptive(
        light: UIColor(red: 0.129, green: 0.118, blue: 0.102, alpha: 1),
        dark: UIColor(red: 0.957, green: 0.922, blue: 0.867, alpha: 1),
        increasedContrastLight: .black,
        increasedContrastDark: .white
    )
    static let secondaryLabel = adaptive(
        light: UIColor(red: 0.435, green: 0.404, blue: 0.369, alpha: 1),
        dark: UIColor(red: 0.667, green: 0.639, blue: 0.604, alpha: 1),
        increasedContrastLight: UIColor(
            red: 0.286,
            green: 0.259,
            blue: 0.231,
            alpha: 1
        ),
        increasedContrastDark: UIColor(
            red: 0.792,
            green: 0.761,
            blue: 0.714,
            alpha: 1
        )
    )
    static let tertiaryLabel = secondaryLabel.opacity(0.72)
    static let border = adaptive(
        light: UIColor(red: 0.847, green: 0.812, blue: 0.757, alpha: 1),
        dark: UIColor(red: 0.204, green: 0.188, blue: 0.169, alpha: 1),
        increasedContrastLight: UIColor(
            red: 0.635,
            green: 0.584,
            blue: 0.514,
            alpha: 1
        ),
        increasedContrastDark: UIColor(
            red: 0.345,
            green: 0.318,
            blue: 0.278,
            alpha: 1
        )
    )
    static let primaryAction = adaptive(
        light: UIColor(red: 0.129, green: 0.118, blue: 0.102, alpha: 1),
        dark: UIColor(red: 0.941, green: 0.890, blue: 0.788, alpha: 1),
        increasedContrastLight: .black,
        increasedContrastDark: .white
    )
    static let primaryActionText = adaptive(
        light: .white,
        dark: UIColor(red: 0.129, green: 0.118, blue: 0.102, alpha: 1),
        increasedContrastLight: .white,
        increasedContrastDark: .black
    )
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)

    private static func adaptive(
        light: UIColor,
        dark: UIColor,
        increasedContrastLight: UIColor,
        increasedContrastDark: UIColor
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return traits.accessibilityContrast == .high
                        ? increasedContrastDark
                        : dark
                }
                return traits.accessibilityContrast == .high
                    ? increasedContrastLight
                    : light
            }
        )
    }
}

enum AlignaSpacing {
    static let zero: CGFloat = 0
    static let micro: CGFloat = 2
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let compact: CGFloat = 12
    static let medium: CGFloat = 16
    static let roomy: CGFloat = 20
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
    static let section: CGFloat = 28
}

enum AlignaRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 18
    static let extraLarge: CGFloat = 24
}

enum AlignaSize {
    static let minimumTouchTarget: CGFloat = 44
    static let standardControlHeight: CGFloat = 52
    static let compactIcon: CGFloat = 36
    static let standardIcon: CGFloat = 44
    static let avatarSmall: CGFloat = 28
    static let avatarMedium: CGFloat = 40
    static let avatarLarge: CGFloat = 48
}

enum AlignaAnimation {
    static let quick: Double = 0.15
    static let standard: Double = 0.25
    static let deliberate: Double = 0.4
    static let appearance: Double = 0.35
}

struct AlignaCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let padding: CGFloat
    private let content: Content

    init(
        padding: CGFloat = AlignaSpacing.medium,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AlignaColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AlignaRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AlignaRadius.large, style: .continuous)
                    .stroke(
                        AlignaColors.border.opacity(colorSchemeContrast == .increased ? 0.7 : 0.28),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 0.5
                    )
            }
    }
}

private struct AlignaCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AlignaColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AlignaRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AlignaRadius.large, style: .continuous)
                    .stroke(
                        AlignaColors.border.opacity(colorSchemeContrast == .increased ? 0.7 : 0.28),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 0.5
                    )
            }
    }
}

extension View {
    func alignaCard(padding: CGFloat = AlignaSpacing.medium) -> some View {
        modifier(AlignaCardModifier(padding: padding))
    }
}
