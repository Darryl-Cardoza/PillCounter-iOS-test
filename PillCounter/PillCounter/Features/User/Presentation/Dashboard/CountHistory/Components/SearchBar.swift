//
//  SearchBar.swift
//  PillCounter
//
//  Created by HC on 09/12/25.
//

import SwiftUI

struct UnderlinedSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var appColors: AppColors
    var onExitSearch: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 1. Left X Button (Exits Search Mode)
            Button(action: onExitSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(appColors.secondary)
            }

            // 2. Search Field with Underline
            VStack(spacing: 8) {
                HStack {
                    TextField("Search", text: $text)
                        .focused($isFocused)
                        .foregroundColor(appColors.text)
                        .tint(appColors.primary)  // Cursor color
                        .submitLabel(.search)
                        .autocorrectionDisabled()

                    // Optional: Small clear button inside field to clear text only
                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(appColors.secondary)
                        }
                    }
                }

                // The Underline
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(appColors.secondary)
            }
        }
        .padding(.vertical, 8)
        // Match the horizontal padding of your list items/header
        .padding(.horizontal, 10)
    }
}
