//
//  PlayerExpandAnimation.swift
//
//
//  Created by Aarav Gupta on 13/04/26.
//

import SwiftUI

public extension Animation {
    static let playerExpandAnimationDuration: TimeInterval = 0.3

    static var playerExpandAnimation: Animation {
        .spring(response: 0.5, dampingFraction: 0.8)
    }

    static var sidebarExpandAnimation: Animation {
        .snappy(duration: playerExpandAnimationDuration)
    }
}
