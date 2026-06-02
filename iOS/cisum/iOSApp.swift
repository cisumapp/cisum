//
//  iOSApp.swift
//  cisum
//
//  Created by Aarav Gupta on 29/11/25.
//

import Core
import Models
import SwiftData
import SwiftUI

@main
struct iOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let cisum = cisumModule()

    var body: some Scene {
        WindowGroup {
            #warning("fonts are not expanded </3")
            cisum.rootView
//                .fontWidth(.expanded)
                .environment(\.playerViewModel, cisum.playerViewModel)
                .persistentSystemOverlays(.hidden)
                .tint(cisum.playerAccentColor)
                .modelContainer(cisum.modelContainer)
                .onOpenURL { url in
                    cisum.handleIncomingURL(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            cisum.handleScenePhaseChange(newPhase)
        }
    }
}
