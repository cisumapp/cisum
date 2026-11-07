//
//  UniversalOverlay.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 03/05/25.
//

import SwiftUI

public struct PlayerOverlayState: Sendable, Equatable {
    public let isExpanded: Bool
    public let progress: Double

    public init(isExpanded: Bool = false, progress: Double = 0.0) {
        self.isExpanded = isExpanded
        self.progress = progress
    }
}

public extension EnvironmentValues {
    @Entry var playerOverlayState: PlayerOverlayState = .init()
}

/// Where a universal overlay is drawn.
public enum UniversalOverlayLayer: Sendable {
    /// The overlay window, above everything in the app: the tab bar, its accessory, alerts.
    case window
    /// Over the current tab's content, inside the main window, so the system tab bar and its
    /// accessory stay on top. Needs a `universalOverlayHost(id:)` around the tab; without one it
    /// falls back to `.window`.
    case tab
}

public extension EnvironmentValues {
    /// The tab host an overlay with `layer: .tab` is drawn into.
    @Entry var universalOverlayHostID: String?
}

#if os(iOS)
public extension View {
    /// - Parameters:
    ///   - animation: animates adding and removing the overlay; `nil` adds and removes it in
    ///     one frame, for content that animates its own appearance.
    ///   - layer: `.window` (above everything) or `.tab` (under the tab bar).
    func universalOverlay(
        animation: Animation? = .easeInOut,
        layer: UniversalOverlayLayer = .window,
        show: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(
            UniversalOverlayModifier(animation: animation, layer: layer, show: show, viewContent: content)
        )
    }

    /// Draws the `layer: .tab` overlays opened inside this view, on top of it. Each tab gets its
    /// own host, so an overlay is drawn once, in the tab that opened it.
    func universalOverlayHost(id: String) -> some View {
        modifier(UniversalOverlayHost(id: id))
    }
}

/// Root View Wrapper
public struct RootView<Content: View>: View {
    private let content: Content
    private let playerOverlayState: PlayerOverlayState
    private let overlayWrapper: (AnyView) -> AnyView
    @State private var properties = UniversalOverlayProperties()

    public init(
        playerOverlayState: PlayerOverlayState,
        @ViewBuilder content: @escaping () -> Content,
        overlayWrapper: @escaping (AnyView) -> AnyView = { $0 }
    ) {
        self.content = content()
        self.playerOverlayState = playerOverlayState
        self.overlayWrapper = overlayWrapper
    }

    public var body: some View {
        content
            .environment(properties)
            .onAppear {
                setupOverlayWindowIfNeeded()
            }
            .onDisappear {
                teardownOverlayWindow()
            }
    }

    private func setupOverlayWindowIfNeeded() {
        guard properties.window == nil, let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }

        let window = PassThroughWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.backgroundColor = .clear
        window.windowLevel = .statusBar + 1
        window.isHidden = false
        window.isUserInteractionEnabled = true

        // Keep a dedicated SwiftUI tree for overlay rendering.
        let rootViewController = UIHostingController(
            rootView: overlayWrapper(
                AnyView(
                    UniversalOverlayViews()
                        .environment(properties)
                )
            )
            .environment(\.playerOverlayState, playerOverlayState)
        )
        rootViewController.view.backgroundColor = .clear
        rootViewController.view.frame = window.bounds
        rootViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = rootViewController
        window.watchAppPresentations()

        properties.window = window
    }

    private func teardownOverlayWindow() {
        properties.views.removeAll(keepingCapacity: false)
        (properties.window as? PassThroughWindow)?.stopWatching()
        properties.window?.isHidden = true
        properties.window = nil
    }
}

/// Shared Universal Overlay Properties
@Observable
class UniversalOverlayProperties {
    var window: UIWindow?
    var views: [OverlayView] = []

    struct OverlayView: Identifiable {
        var id: String = UUID().uuidString
        var view: AnyView
        /// The tab host that draws it; `nil` for the overlay window.
        var hostID: String?
    }
}

private struct UniversalOverlayModifier<ViewContent: View>: ViewModifier {
    var animation: Animation?
    var layer: UniversalOverlayLayer
    @Binding var show: Bool
    @ViewBuilder var viewContent: ViewContent
    /// Local View Properties
    @Environment(UniversalOverlayProperties.self) private var properties
    @Environment(\.universalOverlayHostID) private var hostID
    @State private var viewID: String = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear {
                syncOverlayVisibility()
            }
            .onDisappear {
                removeView()
            }
            .onChange(of: show) { _, _ in
                syncOverlayVisibility()
            }
            .onChange(of: properties.window != nil) { _, isReady in
                if isReady {
                    syncOverlayVisibility()
                }
            }
    }

    private func syncOverlayVisibility() {
        if show {
            addViewIfNeeded()
        } else {
            removeView()
        }
    }

    private func addViewIfNeeded() {
        guard properties.window != nil, !properties.views.contains(where: { $0.id == viewID }) else { return }

        let view = UniversalOverlayProperties.OverlayView(
            id: viewID,
            view: .init(
                viewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            ),
            hostID: layer == .tab ? hostID : nil
        )
        animate { properties.views.append(view) }
    }

    private func removeView() {
        guard properties.views.contains(where: { $0.id == viewID }) else { return }
        animate { properties.views.removeAll(where: { $0.id == viewID }) }
    }

    /// With no animation the change is made in a transaction that disables animations, so a
    /// caller's own animation cannot leak in and fade the overlay out after it already closed.
    private func animate(_ change: () -> Void) {
        if let animation {
            withAnimation(animation, change)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, change)
        }
    }
}

private struct UniversalOverlayViews: View {
    @Environment(UniversalOverlayProperties.self) private var properties

    var body: some View {
        ZStack {
            ForEach(properties.views.filter { $0.hostID == nil }) {
                $0.view
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct UniversalOverlayHost: ViewModifier {
    let id: String
    @Environment(UniversalOverlayProperties.self) private var properties

    func body(content: Content) -> some View {
        content
            .environment(\.universalOverlayHostID, id)
            .overlay {
                ZStack {
                    ForEach(properties.views.filter { $0.hostID == id }) {
                        $0.view
                    }
                }
                .ignoresSafeArea()
            }
    }
}

@Observable
public final class PlayerExpansionState {
    @MainActor public static let shared = PlayerExpansionState()
    public var isExpanded: Bool = false
}

private class PassThroughWindow: UIWindow {
    private var presentationWatch: CADisplayLink?

    /// Sheets, share sheets and alerts the app presents live in its own window, below this one, so
    /// the player sat on top of them. It fades out while any other window is presenting.
    // ponytail: checked ten times a second (one property read per window); a presentation hook
    // would need swizzling.
    func watchAppPresentations() {
        let link = CADisplayLink(target: self, selector: #selector(checkPresentation))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 10, preferred: 10)
        link.add(to: .main, forMode: .common)
        presentationWatch = link
    }

    /// The display link holds this window strongly until it is invalidated.
    func stopWatching() {
        presentationWatch?.invalidate()
        presentationWatch = nil
    }

    @objc private func checkPresentation() {
        let presenting = windowScene?.windows.contains {
            $0 !== self && !$0.isHidden && $0.rootViewController?.presentedViewController != nil
        } ?? false
        let target: CGFloat = presenting ? 0 : 1
        guard alpha != target else { return }
        UIView.animate(withDuration: 0.2) { self.alpha = target }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // If the player is expanded, capture all touches to enable gestures.
        if PlayerExpansionState.shared.isExpanded {
            return super.hitTest(point, with: event)
        }

        guard let hitView = super.hitTest(point, with: event),
              let rootView = rootViewController?.view
        else { return nil }

        if #available(iOS 18, *) {
            for subview in rootView.subviews.reversed() {
                // Finding if any of rootview's child is recieving hit test
                let pointInSubView = subview.convert(point, from: rootView)
                if subview.hitTest(pointInSubView, with: event) != nil {
                    return hitView
                }
            }

            return nil
        } else {
            return hitView == rootView ? nil : hitView
        }
    }
}
#else
public extension View {
    func universalOverlay(
        animation _: Animation? = .easeInOut,
        layer _: UniversalOverlayLayer = .window,
        show _: Binding<Bool>,
        @ViewBuilder content _: @escaping () -> some View
    ) -> some View {
        self
    }

    func universalOverlayHost(id _: String) -> some View {
        self
    }
}

public struct RootView<Content: View>: View {
    var content: Content

    public init(
        playerOverlayState _: PlayerOverlayState,
        @ViewBuilder content: @escaping () -> Content,
        overlayWrapper _: @escaping (AnyView) -> AnyView = { $0 }
    ) {
        self.content = content()
    }

    public var body: some View {
        content
    }
}
#endif
