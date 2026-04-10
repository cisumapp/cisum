//
//  YouTubeEnvironmentKey.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import SwiftUI
import YouTubeSDK

private struct YouTubeEnvironmentKey: EnvironmentKey {
    static var defaultValue: YouTube {
        fatalError("Missing YouTube environment value. Inject it with .environment(\\.youtube, ...).")
    }
}

extension EnvironmentValues {
    var youtube: YouTube {
        get { self[YouTubeEnvironmentKey.self] }
        set { self[YouTubeEnvironmentKey.self] = newValue }
    }
}
