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

    @FocusState private var isFocused: Bool

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
                }
            }
            .focused($isFocused)
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
            if !disabled { isFocused = true }
        }
    }
}
