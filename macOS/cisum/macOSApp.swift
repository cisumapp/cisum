//
//  macOSApp.swift
//  cisum
//
//  Created by Aarav Gupta on 18/03/26.
//

import Aesthetics
import AppKit
import Core
import Models
import Player
import Search
import SwiftData
import SwiftUI
import Utilities
import YouTubeSDK

@main
struct macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Only Settings is a SwiftUI scene. The main window is built in AppKit
        // (`MainWindowFactory`) because SwiftUI would otherwise own the `NSWindow` and rewrite
        // its `styleMask` for `.windowStyle(.hiddenTitleBar)`, undoing `.fullSizeContentView`
        // and leaving a strip above the sidebar.
        Settings {
            appDelegate.cisum.settingsView
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let discord = DiscordModel()
    private(set) lazy var cisum = {
        let timer = PerfLog.start("macos-app-init")
        PerfLog.info("cisum macOS app initializing")
        // Touches `YouTube.shared` and the fallback dependency graph, matching the
        // initialisation order this app used when `WindowGroup` owned the window.
        _ = YouTube.shared
        let module = cisumModule()
        PerfLog.end(timer)
        return module
    }()

    private var window: NSWindow?
    private let searchOverlay = SearchOverlayController()

    func applicationDidFinishLaunching( _: Notification) {
        let root = cisum.rootView
            .environment(searchOverlay)
            .tint(cisum.playerAccentColor)
            .onOpenURL { url in
                PerfLog.info("Handling incoming URL: \(url.absoluteString)")
                self.cisum.handleIncomingURL(url)
            }
            .onAppear { PerfLog.mark("root-view-appeared") }
            .modelContainer(cisum.modelContainer)
            // Publishes the `NSWindow` so `WindowControls` can drive it, and gets the
            // system's own traffic lights out of the way.
            .windowBridge()
            .background { WindowAccessor() }

        let window = MainWindowFactory.make(rootView: root)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        // Showing the window is what triggers the hosted content's first layout pass, and that
        // is where `NSWindow` would shrink itself to the content's fitting size. Re-assert the
        // intended size once that pass has happened.
        MainWindowFactory.applyInitialFrame(to: window)

        discord.start()
        discord.attach(to: cisum.container.playbackServices.player)
        observeLifecycle()
    }

    /// Standard Mac behaviour: closing the last window quits.
    func applicationShouldTerminateAfterLastWindowClosed( _: NSApplication) -> Bool {
        true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        discord.stop()
    }

    func applicationShouldOpenUntitledFile( _: NSApplication) -> Bool {
        window == nil
    }

    /// `onOpenURL` only fires for SwiftUI scenes, so universal and custom links arrive here.
    func application( _: NSApplication, open urls: [URL]) {
        for url in urls {
            cisum.handleIncomingURL(url)
        }
    }

    // MARK: - Lifecycle

    /// A window built in AppKit does not drive SwiftUI's `scenePhase`, so the phase is
    /// translated from `NSApplication`'s own notifications. The only thing the app does with
    /// it is flush pending settings writes when it is no longer active.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cisum.handleScenePhaseChange(.active) }
        }
        center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cisum.handleScenePhaseChange(.inactive) }
        }
        center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cisum.handleScenePhaseChange(.background) }
        }
    }
}
