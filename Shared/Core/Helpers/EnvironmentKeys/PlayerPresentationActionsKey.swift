//
//  PlayerPresentationActionsKey.swift
//  cisum
//
//  Created by Aarav Gupta on 10/04/26.
//

import SwiftUI

struct PlayerPresentationActions {
    var expand: () -> Void = {}
    var collapse: () -> Void = {}
    var toggle: () -> Void = {}
}

extension EnvironmentValues {
    var playerPresentationActions: PlayerPresentationActions {
        get { self[PlayerPresentationActionsKey.self] }
        set { self[PlayerPresentationActionsKey.self] = newValue }
    }
}

private struct PlayerPresentationActionsKey: EnvironmentKey {
    static let defaultValue: PlayerPresentationActions = .init()
}