//
//  macOSApp.swift
//  cisum
//
//  Created by Aarav Gupta on 18/03/26.
//

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
    @Environment(\.scenePhase) private var scenePhase

    private let youtube: YouTube
    private let cisum: cisumModule
    @State private var searchOverlay = SearchOverlayController()

    init() {
        PerfLog.info("cisum macOS app initializing")
        let timer = PerfLog.start("macos-app-init")
        self.youtube = YouTube.shared
        self.cisum = cisumModule()
        PerfLog.end(timer)
    }

    var body: some Scene {
        WindowGroup {
            cisum.rootView
                .environment(searchOverlay)
                .tint(cisum.playerAccentColor)
                .onOpenURL { url in
                    PerfLog.info(" Handling incoming URL: \(url.absoluteString)")
                    cisum.handleIncomingURL(url)
                }
                .onAppear {
                    PerfLog.mark("root-view-appeared")
                }
                .modelContainer(cisum.modelContainer)
                .background { WindowChrome() }
        }
        // Hides the title bar's *text and background* while keeping the window a normal
        // titled, closable, miniaturizable, resizable window: the traffic lights stay, the
        // edges still resize, the green button still zooms, and the title bar's area still
        // drags the window. That is what the reference does — content running to the top
        // of the window with the lights floating over the sidebar.
        //
        // This is deliberately not `.borderless`, which drops the whole title bar and with
        // it every one of those affordances.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .onChange(of: scenePhase) { _, newPhase in
            PerfLog.info("Scene phase changed: \(String(describing: newPhase))")
            cisum.handleScenePhaseChange(newPhase)
        }

        Settings {
            cisum.settingsView
        }
    }
}

// MARK: - Window chrome

/// Makes the window behave the way the layout assumes: content running to the true top
/// edge, no title text, no separator, and the system traffic lights moved into the
/// sidebar's top-left corner.
///
/// The load-bearing part is `.fullSizeContentView`. With it the content view spans the
/// whole window, title bar included, so AppKit stops reserving a strip and stops insetting
/// the safe area. Without it the content is pushed down by a title bar height that no
/// amount of `ignoresSafeArea` can reach, which parks a band of bare window background
/// across the top and leaves the traffic lights stranded above the sidebar panel.
///
/// Scoped to the title bar, the traffic light frames and the layer's radius. It
/// deliberately does not touch `isOpaque` or the background colour, which is where an
/// earlier attempt at custom windowing turned the window transparent.
private struct WindowChrome: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The view is not in a window until after this call returns.
        Task { @MainActor in
            context.coordinator.attach(to: nsView.window)
        }
    }

    /// Owns the window and reapplies the chrome whenever AppKit relayouts the title bar.
    ///
    /// AppKit resets the standard buttons' frames on resize, which would snap them out of
    /// the sidebar the moment the window was resized, so the placement is reapplied rather
    /// than done once.
    final class Coordinator {
        private weak var window: NSWindow?
        /// Observed so the placement survives a resize. Deliberately not torn down in
        /// `deinit`, which cannot touch a non-`Sendable` stored property: the block captures
        /// `self` weakly and the observation is scoped to `object: window`, so it neither
        /// leaks the coordinator nor fires for a closed window. Replaced in `attach`.
        private var resizeObserver: NSObjectProtocol?

        func attach(to window: NSWindow?) {
            guard let window else { return }

            if self.window !== window {
                self.window = window
                if let resizeObserver {
                    NotificationCenter.default.removeObserver(resizeObserver)
                }
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.applyChrome() }
                }
            }

            applyChrome()
        }

        private func applyChrome() {
            guard let window, let contentView = window.contentView else { return }

            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Without this the system still draws its hairline under the title bar, which
            // reads as a stray divider across the top of the sidebar.
            window.titlebarSeparatorStyle = .none

            contentView.wantsLayer = true
            contentView.layer?.masksToBounds = true
            contentView.layer?.cornerRadius = 12
            // `continuous` matches the system's own corner curve, so the override reads as a
            // slightly tighter version of the standard window rather than a hard-cornered box.
            contentView.layer?.cornerCurve = .continuous
        }
    }
}
