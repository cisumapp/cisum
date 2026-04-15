//
//  macOSApp.swift
//  cisum
//
//  Created by Aarav Gupta on 18/03/26.
//

import SwiftUI

@main
struct macOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var dependencies: AppDependencies
    @State private var searchOverlay: SearchOverlayController
    
    init() {
        _dependencies = State(initialValue: AppDependencies.make())
        _searchOverlay = State(initialValue: SearchOverlayController())
    }
    
    var body: some Scene {
        WindowGroup {
            appContent
        }
        .commands {
            CommandMenu("Search") {
                Button("Focus Search Overlay") {
                    searchOverlay.present()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Search Globally") {
                    searchOverlay.switchToGlobalScope(carryCurrentQuery: true)
                    searchOverlay.present()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .defaultSize(width: 1080, height: 840)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase != .active {
                dependencies.prefetchSettings.flushPendingWrites()
                PlaybackControlSettings.shared.flushPendingWrites()
            }
            switch newPhase {
            case .active:
                print("App became active")
            case .inactive:
                print("App became inactive")
            case .background:
                print("App went to background")
            @unknown default:
                print("Unknown scene phase")
            }
        }
        
        Settings {
            SettingsView()
                .injectSettingsDependencies(dependencies)
        }
    }

    @ViewBuilder
    private var appContent: some View {
        ContentView()
            .injectAppDependencies(dependencies)
            .environment(searchOverlay)
            .tint(dependencies.playerViewModel.currentAccentColor)
            .background {
                if #available(macOS 26.0, *) {
                    Rectangle()
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.9))
                }
            }
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .removeWindowDecorations()
    }
}

extension View {
    func removeWindowDecorations() -> some View {
        self
            .background(WindowModifier())
    }
}

struct WindowModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> some NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        DispatchQueue.main.async {
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

#if canImport(HotSwiftUI)
@_exported import HotSwiftUI
#elseif canImport(Inject)
@_exported import Inject
#else
// This code can be found in the Swift package:
// https://github.com/johnno1962/HotSwiftUI or
// https://github.com/krzysztofzablocki/Inject

#if DEBUG
import Combine

public class InjectionObserver: ObservableObject {
    public static let shared = InjectionObserver()
    @Published var injectionNumber = 0
    var cancellable: AnyCancellable? = nil
    let publisher = PassthroughSubject<Void, Never>()
    init() {
        cancellable = NotificationCenter.default.publisher(for:
            Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .sink { [weak self] change in
            self?.injectionNumber += 1
            self?.publisher.send()
        }
    }
}

extension SwiftUI.View {
    public func eraseToAnyView() -> some SwiftUI.View {
        return AnyView(self)
    }
    public func enableInjection() -> some SwiftUI.View {
        return eraseToAnyView()
    }
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
            .onReceive(InjectionObserver.shared.publisher, perform: bumpState)
            .eraseToAnyView()
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
public struct ObserveInjection: DynamicProperty {
    @ObservedObject private var iO = InjectionObserver.shared
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#else
extension SwiftUI.View {
    @inline(__always)
    public func eraseToAnyView() -> some SwiftUI.View { return self }
    @inline(__always)
    public func enableInjection() -> some SwiftUI.View { return self }
    @inline(__always)
    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
        return self
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
@propertyWrapper
public struct ObserveInjection {
    public init() {}
    public private(set) var wrappedValue: Int {
        get {0} set {}
    }
}
#endif
#endif
