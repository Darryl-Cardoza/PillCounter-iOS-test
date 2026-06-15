//
//  BoxesInputField.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import SwiftUI

// MARK: - OTP INPUT VIEW
struct BoxesInputField: View {

    // MARK: - PUBLIC API
    @Binding var otp: [String]
    let length: Int
    let reverse: Bool

    // MARK: - ENVIRONMENT
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject var loginViewModel: LoginViewModel
    @FocusState private var isKeyboardFocused: Bool

    // MARK: - INTERNAL STATE
    @State private var text: String = ""

    // MARK: - INIT
    init(
        otp: Binding<[String]>,
        length: Int = 4,
        reverse: Bool = false
    ) {
        self._otp = otp
        self.length = length
        self.reverse = reverse
    }

    // MARK: - BODY
    var body: some View {
        ZStack {

            // LAYER 1: Invisible TextField (input capture)
            TextField("", text: $text)
                .focused($isKeyboardFocused)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .onChange(of: text) { _, newValue in
                    handleInput(newValue)
                    loginViewModel.errorMessage = nil
                }
                .onAppear {
                    configureInitialState()
                }

            // LAYER 2: Visual Boxes
            HStack(spacing: 15) {
                ForEach(0..<length, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(appColors.inputBackground)
                            .frame(width: 60, height: 80)

                        RoundedRectangle(cornerRadius: 10)
                            .stroke(borderColor(for: index), lineWidth: 2)
                            .frame(width: 60, height: 80)

                        Text(displayChar(at: index))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(appColors.text)
                    }
                    .onTapGesture {
                        isKeyboardFocused = true
                    }
                }
            }
        }
    }

    // MARK: - INITIAL CONFIGURATION
    private func configureInitialState() {
        otp = Array(repeating: reverse ? "0" : "", count: length)
        text = reverse ? "" : otp.joined()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isKeyboardFocused = true
        }
    }

    // MARK: - INPUT HANDLING
    private func handleInput(_ newValue: String) {

        let filtered = newValue.filter { $0.isNumber }
        if filtered != newValue {
            text = filtered
            return
        }

        if filtered.count > length {
            text = String(filtered.prefix(length))
            return
        }

        text = filtered

        var updatedOtp = Array(repeating: reverse ? "0" : "", count: length)

        if reverse {
            let chars = Array(text)
            let startIndex = length - chars.count

            for (i, char) in chars.enumerated() {
                updatedOtp[startIndex + i] = String(char)
            }
        } else {
            for (i, char) in text.enumerated() {
                updatedOtp[i] = String(char)
            }
        }

        otp = updatedOtp

        if text.count == length {
            isKeyboardFocused = false
        }
    }

    // MARK: - DISPLAY LOGIC
    private func displayChar(at index: Int) -> String {
        if reverse {
            return otp[index]
        } else {
            guard index < text.count else { return "" }
            return String(text[text.index(text.startIndex, offsetBy: index)])
        }
    }

    // MARK: - BORDER STYLING
    private func borderColor(for index: Int) -> Color {
        guard isKeyboardFocused else { return .clear }

        if reverse {
            let activeIndex = max(0, (length - 1) - text.count)
            return index == activeIndex ? Color.blue.opacity(0.8) : .clear
        } else {
            if index == text.count { return Color.blue.opacity(0.8) }
            if index == length - 1 && text.count == length {
                return Color.blue.opacity(0.8)
            }
        }
        return .clear
    }
}
