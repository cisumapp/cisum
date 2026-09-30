//
//  WindowDragRegion.swift
//  Aesthetics
//
//  A strip the window can be dragged by, on a borderless window.
//
//  `isMovableByWindowBackground` is the obvious way to make a borderless window movable, and
//  it is the wrong one: it makes *every* piece of empty background draggable, so grabbing the
//  split view's divider to resize the sidebar drags the window instead. The divider is only
//  a few points wide, and a drag that starts a pixel off it lands on background.
//
//  `mouseDownCanMoveWindow` scopes the behaviour to a single view instead, so the sidebar
//  header strip is draggable and nothing else is.
//

#if os(macOS)
import AppKit
import SwiftUI

/// Marks its bounds as a window-drag region. Sized and placed by the caller.
public struct WindowDragRegion: NSViewRepresentable {
    public init() {}

    public func makeNSView(context _: Context) -> NSView {
        DragView()
    }

    public func updateNSView(_ nsView: NSView, context _: Context) {
        // Nothing to update: the behaviour is a property of the view class, not of its state.
    }

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }
    }
}
#endif
