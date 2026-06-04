#if os(iOS)
import SwiftUI
import UIKit

struct CardGesture {
    var handle: (UIPanGestureRecognizer) -> Void
}

extension View {
    func gesture(_ cardGesture: CardGesture) -> some View {
        overlay(alignment: .topLeading) {
            CardGestureBridge(gesture: cardGesture)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
        }
    }
}

private struct CardGestureBridge: UIViewRepresentable {
    let gesture: CardGesture

    func makeUIView(context _: Context) -> GestureHostView {
        GestureHostView(onGesture: gesture.handle)
    }

    func updateUIView(_ uiView: GestureHostView, context _: Context) {
        uiView.onGesture = gesture.handle
        uiView.installIfNeeded()
    }
}

private final class GestureHostView: UIView, UIGestureRecognizerDelegate {
    var onGesture: ((UIPanGestureRecognizer) -> Void)?
    private weak var attachedWindow: UIWindow?
    private weak var installedRecognizer: UIPanGestureRecognizer?

    init(onGesture: ((UIPanGestureRecognizer) -> Void)? = nil) {
        self.onGesture = onGesture
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let window else {
            removeInstalledRecognizer()
            return
        }

        if attachedWindow !== window {
            removeInstalledRecognizer()
            attachedWindow = window
        }

        guard installedRecognizer == nil else { return }

        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        window.addGestureRecognizer(recognizer)
        installedRecognizer = recognizer
    }

    private func removeInstalledRecognizer() {
        guard let recognizer = installedRecognizer else {
            attachedWindow = nil
            return
        }

        attachedWindow?.removeGestureRecognizer(recognizer)
        installedRecognizer = nil
        attachedWindow = nil
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        onGesture?(recognizer)
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if let scrollView = otherGestureRecognizer.view as? UIScrollView {
            let contentOffset = scrollView.contentOffset.y.rounded()

            // Safe Value = 1
            return contentOffset <= 1
        }

        return false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }

        let velocity = panGesture.velocity(in: panGesture.view)
        let locationX = panGesture.location(in: panGesture.view).x

        return (velocity.y > abs(velocity.x)) || (locationX < 30)
    }

    deinit {
        removeInstalledRecognizer()
    }
}
#endif
