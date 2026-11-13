//
//  WindowScrollDirection.swift
//  Aesthetics
//
//  Which way the user is scrolling, in any vertical scroll view in the window.
//

#if os(iOS)
import SwiftUI
import UIKit

public extension View {
    /// Calls `action` with `true` when the user drags any vertical scroll view in this window
    /// towards its end, and `false` when they drag back towards its start or reach the top.
    ///
    /// The tab bar's hide-on-scroll used per-tab scroll hooks, and on iOS 17/18 a UIKit probe that
    /// latched onto the tallest scroll view on screen once and never moved on — so only the tab's
    /// first page hid the bar. This watches the window instead, so pushed pages, other tabs and
    /// cards all behave the same.
    func onWindowScrollDirectionChange(_ action: @escaping (_ scrollingDown: Bool) -> Void) -> some View {
        background {
            WindowScrollObserver(action: action)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

private struct WindowScrollObserver: UIViewRepresentable {
    let action: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        context.coordinator.action = action
        let view = InstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_: InstallerView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleUIView(_: InstallerView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.install(on: window)
        }
    }

    /// A passive pan recognizer on the window: it never cancels or delays a touch and recognizes
    /// alongside everything, so the scroll views, buttons and gestures underneath behave exactly as
    /// before.
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: ((Bool) -> Void)?

        /// How far the finger travels one way before the direction counts. Same as the old hook.
        private let threshold: CGFloat = 20

        private weak var window: UIWindow?
        private weak var scrollView: UIScrollView?
        private var anchorY: CGFloat = 0
        private var lastReported: Bool?

        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            return pan
        }()

        func install(on window: UIWindow?) {
            guard let window, window !== self.window else { return }
            uninstall()
            window.addGestureRecognizer(pan)
            self.window = window
        }

        func uninstall() {
            window?.removeGestureRecognizer(pan)
            window = nil
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            scrollView = Self.verticalScrollView(containing: touch.view)
            return scrollView != nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            let y = pan.translation(in: scrollView).y
            switch pan.state {
            case .began:
                anchorY = y
            case .changed:
                // Finger moving up scrolls the content down.
                if y - anchorY < -threshold {
                    report(true)
                    anchorY = y
                } else if y - anchorY > threshold {
                    report(false)
                    anchorY = y
                }
            case .ended, .cancelled:
                if scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1 {
                    report(false)
                }
            default:
                break
            }
        }

        private func report(_ scrollingDown: Bool) {
            guard lastReported != scrollingDown else { return }
            lastReported = scrollingDown
            action?(scrollingDown)
        }

        /// The nearest scroll view above `view` that scrolls vertically. A horizontal shelf inside a
        /// vertical page is skipped, so dragging a carousel sideways never hides the bar.
        private static func verticalScrollView(containing view: UIView?) -> UIScrollView? {
            var current = view
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView,
                   scrollView.contentSize.height > scrollView.bounds.height - scrollView.adjustedContentInset.top
                       - scrollView.adjustedContentInset.bottom + 1
                {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}
#endif
