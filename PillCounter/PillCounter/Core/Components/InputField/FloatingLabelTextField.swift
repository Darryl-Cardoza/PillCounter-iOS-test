import SwiftUI

// MARK: - FloatingLabelTextField

struct FloatingLabelTextField: View {

    @EnvironmentObject var appColors: AppColors

    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var disabled: Bool = false
    var maxLength: Int? = nil
    /// When true, the field displays a US-formatted phone number — "(XXX) XXX-XXXX" —
    /// while keeping the binding as raw digits only. `maxLength` is interpreted as the
    /// max number of digits (typically 10) rather than max characters.
    var usPhoneFormat: Bool = false

    /// Optional external focus wiring, for callers that need to drive or observe
    /// focus (e.g. Next/Done chaining across sibling fields). When nil, focus is
    /// tracked internally as before.
    var field: AnyHashable? = nil
    var externalFocus: FocusState<AnyHashable?>.Binding? = nil
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil
    var autocorrectionDisabled: Bool = false
    var textInputAutocapitalization: TextInputAutocapitalization? = nil

    @FocusState private var internalFocus: Bool

    private var isFocused: Bool {
        if let externalFocus, let field {
            return externalFocus.wrappedValue == field
        }
        return internalFocus
    }

    private var isActive: Bool {
        isFocused || !text.isEmpty
    }

    /// Formats a raw digit string into US phone format "(XXX) XXX-XXXX".
    private static func formatUSPhone(_ digits: String) -> String {
        let d = digits.filter { $0.isNumber }
        guard !d.isEmpty else { return "" }
        let chars = Array(d)
        var result = "("
        for (i, c) in chars.enumerated() {
            switch i {
            case 3: result += ") "
            case 6: result += "-"
            default: break
            }
            result.append(c)
        }
        return result
    }

    /// Display binding: shows formatted text but writes back raw digits.
    private var displayBinding: Binding<String> {
        Binding(
            get: { usPhoneFormat ? Self.formatUSPhone(text) : text },
            set: { newValue in
                if usPhoneFormat {
                    var digits = newValue.filter { $0.isNumber }
                    if let max = maxLength, digits.count > max {
                        digits = String(digits.prefix(max))
                    }
                    text = digits
                } else {
                    text = newValue
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Floating placeholder label
            Text(placeholder)
                .font(isActive ? .caption : .body)
                .foregroundColor(isFocused ? appColors.primary : appColors.text.opacity(0.75))
                .offset(y: isActive ? -16 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .padding(.leading, 8)

            // Text input
            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .padding(.leading, 8)
                } else {
                    TextField("", text: displayBinding)
                        .padding(.leading, 8)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled(autocorrectionDisabled)
                        .textInputAutocapitalization(textInputAutocapitalization)
                }
            }
            .modifier(FloatingFieldFocusModifier(field: field, externalFocus: externalFocus, internalFocus: $internalFocus))
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .font(.body)
            .foregroundColor(disabled ? appColors.text.opacity(0.75) : appColors.text)
            .padding(.top, isActive ? 10 : 0)
            .opacity(isActive ? 1 : 0)
            .animation(.easeIn(duration: 0.15).delay(0.1), value: isActive)
            .disabled(disabled)
            .onChange(of: text) { _,newValue in
                // For US phone, length is enforced in displayBinding (digit count).
                guard !usPhoneFormat else { return }
                if let max = maxLength, newValue.count > max {
                    text = String(newValue.prefix(max))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 20)
        .frame(height: 64)
        .background(
             appColors.secondaryBackground
        )
        .cornerRadius(10)
        .onTapGesture {
            guard !disabled else { return }
            if let externalFocus, let field {
                externalFocus.wrappedValue = field
            } else {
                internalFocus = true
            }
        }
    }
}

private struct FloatingFieldFocusModifier: ViewModifier {
    let field: AnyHashable?
    let externalFocus: FocusState<AnyHashable?>.Binding?
    var internalFocus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if let field, let externalFocus {
            content.focused(externalFocus, equals: field)
        } else {
            content.focused(internalFocus)
        }
    }
}
