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
    private let cisum: Module
    @State private var searchOverlay = SearchOverlayController()

    init() {
        PerfLog.info("🚀 cisum macOS app initializing")
        let timer = PerfLog.start("macos-app-init")
        self.youtube = YouTube.shared
        self.cisum = cisumModule()
        PerfLog.end(timer)
    }

    var body: some Scene {
        WindowGroup {
            cisum.rootView
                .environment(\.playerViewModel, cisum.playerViewModel)
                .environment(searchOverlay)
                .tint(cisum.playerAccentColor)
                .background {
                    backgroundFill
                }
                .onOpenURL { url in
                    PerfLog.info("💻 Handling incoming URL: \(url.absoluteString)")
                    cisum.handleIncomingURL(url)
                }
                .onAppear {
                    PerfLog.mark("root-view-appeared")
                }
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
                .removeWindowDecorations()
                .modelContainer(cisum.modelContainer)
        }
        .onChange(of: scenePhase) { _, newPhase in
            PerfLog.info("Scene phase changed: \(String(describing: newPhase))")
            cisum.handleScenePhaseChange(newPhase)
        }

        Settings {
            cisum.settingsView
                .environment(\.playerViewModel, cisum.playerViewModel)
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
        } else {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.9))
        }
    }
}

extension View {
    func removeWindowDecorations() -> some View {
        background(WindowModifier())
    }
}

struct WindowModifier: NSViewRepresentable {
    func makeNSView(context _: Context) -> some NSView {
        let view = NSView()

        Task { @MainActor in
            configureWindow(for: view)
        }

        return view
    }

    func updateNSView(_ nsView: NSViewType, context _: Context) {
        Task { @MainActor in
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.backgroundColor = .clear
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        contentView.layer?.cornerCurve = .continuous
    }
}
