//
//  WindowAccessor.swift
//  Aesthetics
//
//  Hands the window to the SwiftUI tree and gets the native traffic lights out of the way.
//
//  Two jobs, both load-bearing:
//
//  1. Hides the three standard window buttons, because `WindowControls` draws its own in
//     the sidebar. Leaving them visible means two sets of lights.
//  2. Publishes the `NSWindow` into the environment so those controls can drive it.
//
//  Deliberately keeps the window *titled* — never `.borderless`, which strips the window
//  controls. `.fullSizeContentView` is what lets the content view span the title bar so
//  nothing is inset below it, while the controls stay ours to place.
//

#if os(macOS)
import AppKit
import SwiftUI

/// Hides the native traffic lights and clears the title bar's chrome.
public struct WindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        // The view is not in a window until after this returns.
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    public func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }

        // The style mask is set once, in `MainWindowFactory`, and is not touched here.
        // A window owned by a SwiftUI `WindowGroup` would have its mask rewritten by
        // `.windowStyle(.hiddenTitleBar)` after this ran; owning the window removes the race.
        // `fullSizeContentView` is only respected for windows with a title bar, and a
        // borderless window cannot become key, so the mask stays titled on purpose.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Without this the system still draws its hairline under the title bar, which reads
        // as a stray divider across the top of the sidebar.
        window.titlebarSeparatorStyle = .none

        // The traffic lights are drawn by `WindowControls` inside the sidebar, since AppKit
        // can only place its own against the window's title bar. Skipped in full screen,
        // where the system brings its own back.
        let hideNative = !window.styleMask.contains(.fullScreen)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = hideNative
        }
    }
}

/// Publishes the enclosing `NSWindow` to `\.window` for this subtree.
///
/// Separate from `WindowAccessor` because an `NSViewRepresentable` cannot write to the
/// environment it is itself installed in — the write has to happen in a modifier wrapped
/// *around* the content.
public struct WindowBridge: ViewModifier {
    @State private var window: NSWindow?

    public init() {}

    public func body(content: Content) -> some View {
        content
            .environment(\.window, window)
            .background {
                WindowReader { window = $0 }
            }
    }

    /// Resolves the window once it exists. `makeNSView` runs before the view is installed,
    /// hence the hop to the main queue.
    private struct WindowReader: NSViewRepresentable {
        let onResolve: (NSWindow?) -> Void

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { onResolve(view.window) }
            return view
        }

        func updateNSView(_ nsView: NSView, context _: Context) {
            DispatchQueue.main.async { onResolve(nsView.window) }
        }
    }
}

public extension View {
    /// Publishes the enclosing `NSWindow` to `\.window` for this subtree.
    func windowBridge() -> some View {
        modifier(WindowBridge())
    }
}
#endif
