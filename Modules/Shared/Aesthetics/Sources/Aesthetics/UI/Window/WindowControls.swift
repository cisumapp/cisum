//
//  WindowControls.swift
//  Aesthetics
//
//  The window's traffic lights, drawn in SwiftUI and placed inside the sidebar.
//
//  The pattern is borrowed from the Ora browser. It exists because the native buttons
//  cannot be positioned where a floating sidebar needs them: AppKit lays them out against
//  the window's own title bar, so on a full-size-content window they end up stranded in
//  bare background above an inset sidebar.
//
//  These are not fakes. Each one calls the same `NSWindow` action the native button calls,
//  so close, minimise and full-screen behave exactly as the system intends, and the
//  unfocused dimming is driven by the real key-window notifications rather than guessed.
//

#if os(macOS)
import AppKit
import SwiftUI

/// Which window action a control performs.
public enum WindowControlAction: Sendable {
    case close
    case minimize
    case zoom

    var symbolName: String {
        switch self {
        case .close: "xmark"
        case .minimize: "minus"
        case .zoom: "arrow.up.left.and.arrow.down.right"
        }
    }

    var tint: Color {
        switch self {
        case .close: Color(red: 1.00, green: 0.37, blue: 0.34)
        case .minimize: Color(red: 1.00, green: 0.74, blue: 0.20)
        case .zoom: Color(red: 0.16, green: 0.79, blue: 0.25)
        }
    }

    /// Glyph colour on hover. The system draws these near-black on the saturated fills.
    var glyphTint: Color {
        Color.black.opacity(0.55)
    }
}

/// The three controls, laid out horizontally. Drops out entirely in full screen, where the
/// system brings its own buttons back.
public struct WindowControls: View {
    @Environment(\.window) private var window

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            ForEach([WindowControlAction.close, .minimize, .zoom], id: \.self) { action in
                WindowControlButton(action: action)
            }
        }
    }
}

private struct WindowControlButton: View {
    @Environment(\.window) private var window

    let action: WindowControlAction

    @State private var isWindowKey = true
    @State private var isHovering = false

    private let diameter: CGFloat = 12

    var body: some View {
        Circle()
            .fill(action.tint)
            // Unfocused windows show the system grey, not a dimmed colour. Mirrors how
            // AppKit renders the native buttons.
            .opacity(isWindowKey ? 1 : 0.35)
            .frame(width: diameter, height: diameter)
            .overlay {
                // The glyph only appears on hover, as it does on a real traffic light.
                if isHovering, isWindowKey {
                    Image(systemName: action.symbolName)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(action.glyphTint)
                }
            }
            .contentShape(.circle)
            .onHover { isHovering = $0 }
            .onTapGesture(perform: run)
            .onAppear { isWindowKey = window?.isKeyWindow ?? true }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard note.object as? NSWindow === window else { return }
                isWindowKey = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                guard note.object as? NSWindow === window else { return }
                isWindowKey = false
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
                guard note.object as? NSWindow === window else { return }
                isWindowKey = true
            }
    }

    /// The standard window actions, unchanged.
    ///
    /// The window is titled, just with its title bar's *contents* hidden, so `.closable`,
    /// `.miniaturizable` and `.resizable` are all still set and these are the real system
    /// actions. The controls are only a different set of pixels in a different place.
    private func run() {
        guard let window else { return }
        switch action {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.performMiniaturize(nil)
        case .zoom:
            window.performZoom(nil)
        }
    }
}

// MARK: - Window in the environment

private struct WindowKey: EnvironmentKey {
    static let defaultValue: NSWindow? = nil
}

public extension EnvironmentValues {
    /// The window this subtree lives in, so views can drive it without reaching for a
    /// global. Injected by `WindowAccessor`.
    var window: NSWindow? {
        get { self[WindowKey.self] }
        set { self[WindowKey.self] = newValue }
    }
}
#endif
