//
//  iOSApp.swift
//  cisum
//
//  Created by Aarav Gupta on 29/11/25.
//

import Aesthetics
import Core
import Models
import SwiftData
import SwiftUI
import Utilities

@main
struct iOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let cisum: cisumModule

    init() {
        PerfLog.info("cisum iOS app initializing")
        let timer = PerfLog.start("ios-app-init")
        self.cisum = cisumModule()
        PerfLog.end(timer)
    }

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
                    PerfLog.info("Handling incoming URL: \(url.absoluteString)")
                    cisum.handleIncomingURL(url)
                }
                .onAppear {
                    PerfLog.mark("root-view-appeared")
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            PerfLog.info("Scene phase changed: \(String(describing: newPhase))")
            cisum.handleScenePhaseChange(newPhase)
        }
    }
}
