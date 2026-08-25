import SwiftUI
import UIKit

struct AuthScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    var showsBrand = true
    var motionNamespace: Namespace.ID?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        showsBrand: Bool = true,
        motionNamespace: Namespace.ID? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBrand = showsBrand
        self.motionNamespace = motionNamespace
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlignaSpacing.large) {
                if let motionNamespace {
                    authHeader
                        .matchedGeometryEffect(
                            id: "auth.header",
                            in: motionNamespace
                        )
                } else {
                    authHeader
                }

                if let motionNamespace {
                    authCard
                        .matchedGeometryEffect(
                            id: "auth.card",
                            in: motionNamespace
                        )
                } else {
                    authCard
                }
            }
            .padding(.horizontal, AlignaSpacing.roomy)
            .padding(.top, AlignaSpacing.roomy)
            .padding(.bottom, AlignaSpacing.extraLarge)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AlignaColors.background)
    }

    private var authHeader: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.compact) {
            if showsBrand {
                AlignaBrandMarkView()
                    .padding(.bottom, AlignaSpacing.small)
            }

            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(AlignaColors.label)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(AlignaColors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var authCard: some View {
        content
            .padding(AlignaSpacing.roomy)
            .background(AlignaColors.surface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AlignaRadius.large,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AlignaRadius.large,
                    style: .continuous
                )
                .stroke(AlignaColors.border.opacity(0.55), lineWidth: 0.5)
            }
    }
}

struct AlignaBrandMarkView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var size: CGFloat = 72

    var body: some View {
        Image("AlignaBrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: size * 0.22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: size * 0.22,
                    style: .continuous
                )
                .stroke(AlignaColors.border.opacity(0.28), lineWidth: 0.5)
            }
            .scaleEffect(isBreathing ? 1.012 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 1.8)
                        .repeatForever(autoreverses: true)
                ) {
                    isBreathing = true
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    withAnimation(nil) {
                        isBreathing = false
                    }
                }
            }
            .accessibilityLabel("Aligna")
    }
}

struct AuthTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var systemImage: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrectionDisabled = false
    var submitLabel: SubmitLabel = .next
    var errorMessage: String?
    var isFocused = false
    var labelActionTitle: String?
    var onLabelAction: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}

    @FocusState private var internalFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.small) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AlignaColors.label)

                Spacer()

                if let labelActionTitle {
                    Button(labelActionTitle, action: onLabelAction)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                }
            }

            HStack(spacing: AlignaSpacing.compact) {
                Image(systemName: systemImage)
                    .foregroundStyle(
                        internalFocus
                            ? AlignaColors.accent
                            : AlignaColors.secondaryLabel
                    )
                    .frame(width: 20)
                    .accessibilityHidden(true)

                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder)
                        .foregroundStyle(AlignaColors.tertiaryLabel)
                )
                .focused($internalFocus)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
            }
            .padding(.horizontal, AlignaSpacing.medium)
            .frame(minHeight: 54)
            .background(AlignaColors.elevatedSurface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AlignaRadius.medium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AlignaRadius.medium,
                    style: .continuous
                )
                .stroke(
                    fieldBorderColor,
                    lineWidth: internalFocus || errorMessage != nil ? 1.5 : 0.5
                )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                internalFocus = true
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AlignaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            internalFocus = isFocused
        }
        .onChange(of: isFocused) { _, newValue in
            guard internalFocus != newValue else { return }
            internalFocus = newValue
        }
        .onChange(of: internalFocus) { _, newValue in
            onFocusChange(newValue)
        }
    }

    private var fieldBorderColor: Color {
        if errorMessage != nil {
            return AlignaColors.danger
        }
        if internalFocus {
            return AlignaColors.accent
        }
        return AlignaColors.border.opacity(0.45)
    }
}

struct SecureAuthField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let textContentType: UITextContentType
    var returnKey: AuthReturnKey = .next
    var errorMessage: String?
    var isFocused = false
    var labelActionTitle: String?
    var onLabelAction: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.small) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AlignaColors.label)

                Spacer()

                if let labelActionTitle {
                    Button(labelActionTitle, action: onLabelAction)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: AlignaSize.minimumTouchTarget)
                }
            }

            HStack(spacing: AlignaSpacing.compact) {
                Image(systemName: "lock")
                    .foregroundStyle(
                        isFocused
                            ? AlignaColors.accent
                            : AlignaColors.secondaryLabel
                    )
                    .frame(width: 20)
                    .accessibilityHidden(true)

                PasswordTextField(
                    text: $text,
                    placeholder: placeholder,
                    textContentType: textContentType,
                    isSecure: !isRevealed,
                    isFirstResponder: isFocused,
                    returnKey: returnKey,
                    onFocusChange: onFocusChange,
                    onSubmit: onSubmit
                )
                .frame(maxWidth: .infinity, minHeight: 24)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AlignaColors.secondaryLabel)
                .accessibilityLabel(
                    isRevealed ? "Hide \(label)" : "Show \(label)"
                )
            }
            .padding(.leading, AlignaSpacing.medium)
            .padding(.trailing, AlignaSpacing.small)
            .frame(minHeight: 54)
            .background(AlignaColors.elevatedSurface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AlignaRadius.medium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AlignaRadius.medium,
                    style: .continuous
                )
                .stroke(
                    fieldBorderColor,
                    lineWidth: isFocused || errorMessage != nil ? 1.5 : 0.5
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AlignaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var fieldBorderColor: Color {
        if errorMessage != nil {
            return AlignaColors.danger
        }
        if isFocused {
            return AlignaColors.accent
        }
        return AlignaColors.border.opacity(0.45)
    }
}

enum AuthReturnKey {
    case next
    case go
    case done

    var uiValue: UIReturnKeyType {
        switch self {
        case .next:
            .next
        case .go:
            .go
        case .done:
            .done
        }
    }
}

private struct PasswordTextField: UIViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let textContentType: UITextContentType
    let isSecure: Bool
    let isFirstResponder: Bool
    let returnKey: AuthReturnKey
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.clearButtonMode = .never
        field.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        configure(field)
        field.isSecureTextEntry = isSecure
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        configure(field)

        if field.text != text, field.markedTextRange == nil {
            field.text = text
        }

        if field.isSecureTextEntry != isSecure {
            let preservedText = field.text
            let selectedRange = field.selectedTextRange
            field.isSecureTextEntry = isSecure
            field.text = preservedText
            field.selectedTextRange = selectedRange
        }

        DispatchQueue.main.async {
            if isFirstResponder, !field.isFirstResponder {
                field.becomeFirstResponder()
            } else if !isFirstResponder, field.isFirstResponder {
                field.resignFirstResponder()
            }
        }
    }

    private func configure(_ field: UITextField) {
        field.placeholder = placeholder
        field.textContentType = textContentType
        field.returnKeyType = returnKey.uiValue

        if textContentType == .newPassword {
            field.passwordRules = UITextInputPasswordRules(
                descriptor: "required: upper; required: lower; required: digit; minlength: 8;"
            )
        } else {
            field.passwordRules = nil
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PasswordTextField

        init(parent: PasswordTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.text = textField.text ?? ""
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.text = textField.text ?? ""
            parent.onSubmit()
            return false
        }
    }
}

struct PrimaryAuthButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AlignaSpacing.small) {
                if isLoading {
                    ProgressView()
                        .tint(AlignaColors.primaryActionText)
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(AlignaColors.primaryActionText)
            .frame(
                maxWidth: .infinity,
                minHeight: AlignaSize.standardControlHeight
            )
            .background(AlignaColors.primaryAction)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AlignaRadius.medium,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled && !isLoading ? 1 : 0.48)
        .accessibilityValue(isLoading ? "In progress" : "")
    }
}

struct AuthErrorBanner: View {
    enum Style {
        case error
        case success
        case information

        var color: Color {
            switch self {
            case .error:
                AlignaColors.danger
            case .success:
                AlignaColors.success
            case .information:
                AlignaColors.accent
            }
        }

        var symbol: String {
            switch self {
            case .error:
                "exclamationmark.triangle.fill"
            case .success:
                "checkmark.circle.fill"
            case .information:
                "info.circle.fill"
            }
        }
    }

    let message: String
    var style: Style = .error

    var body: some View {
        Label(message, systemImage: style.symbol)
            .font(.subheadline)
            .foregroundStyle(AlignaColors.label)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AlignaSpacing.compact)
            .background(style.color.opacity(0.11))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AlignaRadius.small,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AlignaRadius.small,
                    style: .continuous
                )
                .stroke(style.color.opacity(0.28), lineWidth: 0.5)
            }
            .accessibilityElement(children: .combine)
    }
}

struct AuthStepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.small) {
            Text("Step \(currentStep) of \(totalSteps)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AlignaColors.secondaryLabel)

            ProgressView(
                value: Double(currentStep),
                total: Double(totalSteps)
            )
            .progressViewStyle(.linear)
            .tint(AlignaColors.accent)
            .animation(
                .easeInOut(duration: AlignaAnimation.deliberate),
                value: currentStep
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Account creation, step \(currentStep) of \(totalSteps)"
        )
    }
}

struct PasswordRequirementsView: View {
    let password: String

    private var requirements: [(String, Bool)] {
        [
            ("8 or more characters", password.count >= 8),
            (
                "Uppercase and lowercase letters",
                password.rangeOfCharacter(from: .uppercaseLetters) != nil
                    && password.rangeOfCharacter(
                        from: .lowercaseLetters
                    ) != nil
            ),
            (
                "At least one number",
                password.rangeOfCharacter(from: .decimalDigits) != nil
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AlignaSpacing.extraSmall) {
            ForEach(requirements, id: \.0) { requirement in
                Label(
                    requirement.0,
                    systemImage: requirement.1
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.caption)
                .foregroundStyle(
                    requirement.1
                        ? AlignaColors.success
                        : AlignaColors.secondaryLabel
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

@MainActor
enum AuthHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

#Preview("Authentication components") {
    AuthScaffold(
        title: "Welcome back",
        subtitle: "Your meetings, decisions, and next steps—all in one place."
    ) {
        VStack(spacing: AlignaSpacing.medium) {
            AuthTextField(
                label: "Email",
                placeholder: "name@example.com",
                text: .constant("john@example.com"),
                systemImage: "envelope"
            )
            SecureAuthField(
                label: "Password",
                placeholder: "Enter your password",
                text: .constant("Aligna2026"),
                textContentType: .password
            )
            PrimaryAuthButton(
                title: "Sign In"
            ) {}
        }
    }
}
