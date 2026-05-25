//
//  CountStabilizer.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import Foundation

final class CountStabilizer {

    private let window: Int
    private var history: [Int] = []

    init(windowSize: Int) {
        self.window = windowSize
    }

    func update(rawCount: Int) -> Int {
        history.append(rawCount)
        if history.count > window { history.removeFirst() }

        return Int(history.sorted()[history.count / 2])
    }
}
