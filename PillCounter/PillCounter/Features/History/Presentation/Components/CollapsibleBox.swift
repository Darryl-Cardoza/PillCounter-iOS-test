//
//  CollapsibleBox.swift
//  PillCounter
//
//  Created by Bhushan Patil on 22/04/26.
//
import SwiftUI

struct CollapsibleBox<Content: View>: View {

    let title: String
    let content: Content
    var allowCollapse: Bool = true
    let bgColor: Color?

    @State private var isExpanded: Bool

    @EnvironmentObject private var appColors: AppColors

    init(
        title: String,
        allowCollapse: Bool = true,
        defaultExpanded: Bool = false,
        bgColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.allowCollapse = allowCollapse
        self._isExpanded = State(initialValue: allowCollapse ? defaultExpanded : true)
        self.content = content()
        self.bgColor = bgColor
    }

  
    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appColors.primary)

                Spacer()

                if allowCollapse{
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut, value: isExpanded)
                        .foregroundStyle(appColors.primary)
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                if allowCollapse{
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isExpanded.toggle()
                    }
                }
            }

            // CONTENT
            if isExpanded {
                content
                    .padding()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .background(bgColor ?? appColors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
