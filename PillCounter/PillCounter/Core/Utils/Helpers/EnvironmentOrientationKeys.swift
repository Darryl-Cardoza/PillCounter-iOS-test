//
//  EnvironmentOrientationKeys.swift
//  PillCounter
//
//  Created by HC on 07/11/25.
//

import SwiftUI

private struct IsLandscapeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isLandscape: Bool {
        get { self[IsLandscapeKey.self] }
        set { self[IsLandscapeKey.self] = newValue }
    }
}
