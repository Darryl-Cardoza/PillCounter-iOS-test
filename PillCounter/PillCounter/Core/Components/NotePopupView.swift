//
//  NotePopupView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 28/04/26.
//
//
//  NotePopupView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 28/04/26.
//
import SwiftUI

struct NotePopupView: View {

    // MARK: - Configuration
    let title: String
    let showClose: Bool
    let placeholder: String

    @Binding var text: String
    var errorMessage: String?

    // MARK: - Buttons
    /// Primary button (right / only button) — always shown
    let primaryTitle: String
    let primaryAction: () -> Void

    /// Secondary button (left, outline style) — shown only when provided
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    /// Close button in header — shown only when showClose == true
    let onClose: (() -> Void)?

    @EnvironmentObject private var appColors: AppColors

    // MARK: - Convenience inits

    /// Single-button variant (e.g. "Would you like to add a note?" with just YES)
    init(
        title: String,
        placeholder: String = L10n.Common.typeHere,
        showClose: Bool = false,
        text: Binding<String>,
        errorMessage: String? = nil,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.title           = title
        self.placeholder     = placeholder
        self.showClose       = showClose
        self._text           = text
        self.errorMessage    = errorMessage
        self.primaryTitle    = primaryTitle
        self.primaryAction   = primaryAction
        self.secondaryTitle  = nil
        self.secondaryAction = nil
        self.onClose         = onClose
    }

    /// Two-button variant (e.g. CANCEL + YES, or SKIP + SAVE)
    init(
        title: String,
        placeholder: String = L10n.Common.typeHere,
        showClose: Bool = false,
        text: Binding<String>,
        errorMessage: String? = nil,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.title           = title
        self.placeholder     = placeholder
        self.showClose       = showClose
        self._text           = text
        self.errorMessage    = errorMessage
        self.primaryTitle    = primaryTitle
        self.primaryAction   = primaryAction
        self.secondaryTitle  = secondaryTitle
        self.secondaryAction = secondaryAction
        self.onClose         = onClose
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── HEADER ──────────────────────────────────────────────
            HStack {
              

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(appColors.text)
                    .frame(maxWidth:.infinity, alignment: .leading)

                Spacer()

                if showClose {
                    Button { onClose?() } label: {
                        Image(systemName: "xmark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundStyle(appColors.text)
                    }
                }
            }

            // ── TEXT EDITOR ─────────────────────────────────────────
            PillCounterTextEditor(
                imageName: nil,
                placeholder: placeholder,
                disabled: false,
                text: $text
            )
            .frame(minHeight: 120)

            // ── VALIDATION ERROR ────────────────────────────────────
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .padding(.top, -12)
            }

            // ── ACTION BUTTONS ──────────────────────────────────────
            if let secondaryTitle, let secondaryAction {
                // Two-button layout: secondary (outline) left, primary (filled) right
                HStack(spacing: 12) {
                    PillCountingButton(
                        iconName: nil,
                        title: secondaryTitle,
                        textColor: appColors.primary,
                        backgroundColor: .clear,
                        borderColor: appColors.primary,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 0,
                        verticalPadding: 14,
                        iconSize: 0,
                        action: secondaryAction
                    )
                    .frame(maxWidth: .infinity)

                    PillCountingButton(
                        iconName: nil,
                        title: primaryTitle,
                        textColor: appColors.text,
                        backgroundColor: appColors.primary,
                        borderColor: .clear,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 0,
                        verticalPadding: 14,
                        iconSize: 0,
                        action: primaryAction
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Single-button layout: full width
                HStack{
                    PillCountingButton(
                        iconName: nil,
                        title: primaryTitle,
                        textColor: appColors.text,
                        backgroundColor: appColors.primary,
                        borderColor: .clear,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 0,
                        verticalPadding: 14,
                        iconSize: 0,
                        action: primaryAction
                    )
                    .frame(maxWidth: 120)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(width: 300)
        .background(appColors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
