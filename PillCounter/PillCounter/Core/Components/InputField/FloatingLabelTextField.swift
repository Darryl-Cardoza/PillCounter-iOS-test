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

    @FocusState private var isFocused: Bool

    private var isActive: Bool {
        isFocused || !text.isEmpty
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
                    TextField("", text: $text)
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
