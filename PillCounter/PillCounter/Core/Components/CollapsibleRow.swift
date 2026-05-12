//
//  CollapsibleRow.swift
//  PillCounter
//
//  Created by Bhushan Patil on 06/05/26.
//

// MARK: - CollapsibleRow.swift
// Add this file to your project — reusable across any list

import SwiftUI

struct CollapsibleRow: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.88, anchor: .center)
            .opacity(isVisible ? 1 : 0)
            .frame(maxHeight: isVisible ? .infinity : 0, alignment: .top)
            .clipped()
    }
}

extension View {
    func collapsible(isVisible: Bool) -> some View {
        self.modifier(CollapsibleRow(isVisible: isVisible))
    }
}
