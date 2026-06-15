//
//  Router.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI

final class Router : ObservableObject {
    
    @Published var navigationPath = NavigationPath()
    
    // temporary value holding the type selected.
    var selectedPillScanningType: CountType?
    
    func setRoot(to destination: PillCounterFlow) {
        navigationPath = NavigationPath()
        navigationPath.append(destination)
    }
    
    func navigate(to destination: PillCounterFlow) {
        navigationPath.append(destination)
    }
    
    func navigateBack() {
        navigationPath.removeLast()
    }
    
    func navigateToRoot() {
        navigationPath.removeLast(navigationPath.count)
    }
}
