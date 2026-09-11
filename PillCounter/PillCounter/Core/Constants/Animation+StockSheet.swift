//
//  Animation+StockSheet.swift
//  PillCounter
//

import SwiftUI

extension Animation {
    /// Curve used by UnifiedCameraView's stock-count sheet resize and
    /// StockCountBatchBottomSheet's drag/snap — both sides must match or the
    /// parent frame and child content visibly step apart mid-animation.
    static let stockSheetResize = Animation.spring(response: 0.35, dampingFraction: 0.78)
}
