//
//  PlayerExpandAnimation.swift
//  
//
//  Created by Aarav Gupta on 13/04/26.
//

import SwiftUI

extension Animation {
    static let playerExpandAnimationDuration: TimeInterval = 0.3
    static var playerExpandAnimation: Animation {
        .smooth(duration: playerExpandAnimationDuration, extraBounce: 0)
    }
    
    static var sidebarExpandAnimation: Animation {
        .snappy(duration: playerExpandAnimationDuration)
    }
}
