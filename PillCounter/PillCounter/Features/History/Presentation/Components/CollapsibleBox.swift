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
    var countText: String? = nil

    @State private var isExpanded: Bool

    @EnvironmentObject private var appColors: AppColors

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var showChevron: Bool {
        allowCollapse && !isPad
    }

    init(
        title: String,
        allowCollapse: Bool = true,
        defaultExpanded: Bool = false,
        bgColor: Color? = nil,
        countText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.allowCollapse = allowCollapse
        self._isExpanded = State(initialValue: allowCollapse ? defaultExpanded : true)
        self.content = content()
        self.bgColor = bgColor
        self.countText = countText
    }


    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appColors.primary)

                Spacer()

                if let countText {
                    Text(countText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appColors.primary)
                        .padding(.trailing, showChevron ? 8 : 0)
                }

                if showChevron {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut, value: isExpanded)
                        .foregroundStyle(appColors.primary)
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                if allowCollapse && !isPad {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isExpanded.toggle()
                    }
                }
            }

            // CONTENT
            if isExpanded || isPad {
                content
                    .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .background(bgColor ?? appColors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
