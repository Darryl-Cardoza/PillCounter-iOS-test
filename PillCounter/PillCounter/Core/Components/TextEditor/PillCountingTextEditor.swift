//
//  PillCountingTextEditor.swift
//  PillCounter
//
//  Created by HC on 20/11/25.
//

import SwiftUI

struct PillCounterTextEditor: View {
    @EnvironmentObject private var appColors: AppColors

    let imageName: String?
    let placeholder: String
    let disabled: Bool

    @Binding var text: String

    var minHeight: CGFloat = 90
    var maxHeight: CGFloat = 180

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // MARK: - Icon on Left
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .padding(.leading, 15)
                    .padding(.top, 10)
                    .foregroundColor(appColors.secondary)

                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 2, height: minHeight - 10)
                    .padding(.trailing, 10)
            }

            // MARK: - TextEditor with placeholder support
            ZStack(alignment: .topLeading) {
                // Placeholder
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(appColors.text.opacity(0.4))
                        .padding(.top, 6)
                        .padding(.leading, 5)
                }

                TextEditor(text: $text)
                    .foregroundColor(appColors.text)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .disabled(disabled)
                    .scrollContentBackground(.hidden)
                    .padding(.leading, 4) // aligns cursor with placeholder
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 12)
        .background(appColors.secondaryBackground)
        .cornerRadius(8)
    }
}
