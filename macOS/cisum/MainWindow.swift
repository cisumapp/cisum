//
//  MainWindow.swift
//  cisum (macOS)
//
//  Creates the app's window directly in AppKit, the way the Ora browser does.
//
//  Why not a SwiftUI `WindowGroup`: SwiftUI owns the window it creates and applies
//  `.windowStyle(.hiddenTitleBar)` to it, which rewrites `styleMask` after any
//  `NSViewRepresentable` in the tree has run. Every attempt to opt into
//  `.fullSizeContentView` from inside the view hierarchy was racing that write, which is why
//  the strip across the top of the window kept surviving. Owning the window means the mask
//  is set once, at construction, and never touched again.
//
//  The mask is deliberately titled. Per Apple's documentation for `fullSizeContentView`,
//  it is "respected only for windows with a title bar", and a borderless window cannot
//  become key — which would silently break type-ahead, ⌘C/⌘V and every text field. Titled
//  also keeps the system corner radius and the native resize edges.
//
//  `.fullSizeContentView` makes the content view span the whole window. What removes the
//  remaining strip is `ignoresSafeArea(.all)` on the SwiftUI content, because AppKit lays
//  views out against the window's *content layout rect*, which still excludes the title bar.
//

import AppKit
import SwiftUI

@MainActor
enum MainWindowFactory {
    /// The window's opening size, in points.
    ///
    /// Chosen to frame the shell well: enough width that the sidebar and the record band sit
    /// side by side without the content columns going cramped, and a height that shows a
    /// couple of rows of the grid below the transport.
    static let defaultSize = NSSize(width: 1098, height: 851)

    /// Smallest the window is allowed to get, in points.
    ///
    /// Needed because the content is SwiftUI: an `NSHostingController` can report a small
    /// fitting size early in layout, and `NSWindow` will shrink to fit it. Without a floor the
    /// window collapsed to 611×98 — 190 (sidebar minimum) + 420 (detail minimum) + the
    /// divider — which is the split view's smallest legal width and almost no height.
    static let minimumSize = NSSize(width: 860, height: 560)

    static func make(rootView: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            // `fullSizeContentView` is the whole point; the rest keep the window a normal
            // Mac window.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Nothing drawn in the title bar, and no separator line under it.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // With the title bar's contents gone, dragging has to come from the content.
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = minimumSize

        window.contentViewController = NSHostingController(rootView: rootView)
        applyInitialFrame(to: window)
        return window
    }

    /// Places the window at `defaultSize`, centred on the screen.
    ///
    /// Called again once the window is on screen: showing it is what triggers the hosted
    /// content's first layout pass, which is when the window would otherwise shrink itself.
    static func applyInitialFrame(to window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            window.setContentSize(defaultSize)
            return
        }
        // Never open larger than the screen can show, so the window is fully visible on a
        // smaller display.
        let available = screen.visibleFrame
        let size = NSSize(
            width: min(defaultSize.width, available.width),
            height: min(defaultSize.height, available.height)
        )
        window.setContentSize(size)
        window.setFrameOrigin(
            NSPoint(
                x: available.midX - size.width / 2,
                y: available.midY - size.height / 2
            )
        )
    }
}
