//
//  IdNameSheetContent.swift
//  PillCounter
//
//  Editable first/last name fields + tap-to-fill suggestion chips + Continue.
//  Reached either by a confirmed scan or by "Enter Manually" — this sheet is
//  the only name-entry UI in the enrollment flow now. See
//  plans/face-auth/ocr/19-08-2026-12-31-ocr-id-scan.md §4.3.
//

import SwiftUI

struct IdNameSheetContent: View {

    @Binding var firstName: String
    @Binding var lastName: String
    @ObservedObject var viewModel: IdScanViewModel
    let onContinue: () -> Void

    @EnvironmentObject private var appColors: AppColors
    @FocusState private var focusedField: AnyHashable?

    private var focusedNameField: NameField? { focusedField as? NameField }

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.FaceAuth.whatsYourName)
                .font(.title3.bold())
                .foregroundStyle(appColors.primary)

            nameField(
                placeholder: L10n.FaceAuth.firstNameFieldPlaceholder,
                text: $firstName,
                field: .first
            )
            nameField(
                placeholder: L10n.FaceAuth.lastNameFieldPlaceholder,
                text: $lastName,
                field: .last
            )

            if let nameError = viewModel.nameError {
                Text(nameError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            if !viewModel.suggestions.isEmpty {
                suggestionChips
            }

            Spacer(minLength: 0)

            FaceAuthActionButton(
                title: L10n.FaceAuth.continueButton,
                isPrimary: true,
                isEnabled: canContinue,
                fillsWidth: true
            ) {
                focusedField = nil
                onContinue()
            }
            .padding(.bottom, 12)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.primaryBackground)
        .onChange(of: focusedField) { _, newValue in
            // Whenever a cursor exists it is in the highlighted field — a
            // direct tap on a field re-syncs activeField the same way a scan
            // result or a chip tap does.
            if let newValue = newValue as? NameField { viewModel.activeField = newValue }
        }
    }

    // MARK: - Fields

    private func nameField(placeholder: String, text: Binding<String>, field: NameField) -> some View {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            field: field,
            externalFocus: $focusedField,
            submitLabel: field == .first ? .next : .done,
            onSubmit: {
                if field == .first {
                    focusedField = NameField.last
                } else if canContinue {
                    focusedField = nil
                    onContinue()
                }
            },
            autocorrectionDisabled: true,
            textInputAutocapitalization: .words
        )
        // Target highlight: visible only when no field is focused —
        // chip-tap mode — matching Android's unfocused*-only override.
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    focusedNameField == nil && viewModel.activeField == field ? appColors.primary : .clear,
                    lineWidth: 2
                )
        )
    }

    // MARK: - Suggestion chips

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestionsLabel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(appColors.text.opacity(0.7))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(viewModel.suggestions, id: \.self) { word in
                    Button {
                        // A chip tap always clears the cursor — the keyboard
                        // never appears in chip-pick mode.
                        focusedField = nil
                        viewModel.chipTapped(word)
                    } label: {
                        Text(word)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(appColors.secondaryBackground)
                            )
                            .foregroundStyle(appColors.text)
                    }
                }
            }
        }
    }

    private var suggestionsLabel: String {
        let fieldName = viewModel.activeField == .first
            ? L10n.FaceAuth.firstNameFieldPlaceholder
            : L10n.FaceAuth.lastNameFieldPlaceholder
        return String(format: L10n.FaceAuth.IdScan.suggestionsLabel, fieldName)
    }
}
