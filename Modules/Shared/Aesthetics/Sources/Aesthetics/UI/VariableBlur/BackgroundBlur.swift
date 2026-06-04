//
//  BackgroundBlur.swift
//
//
//  Created by Aarav Gupta on 23/04/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
public struct BackgroundBlur: UIViewRepresentable {
    public var radius: CGFloat

    public init(radius: CGFloat) {
        self.radius = radius
    }

    public func makeUIView(context _: Context) -> BackgroundBlurView {
        BackgroundBlurView(radius: radius)
    }

    public func updateUIView(_: BackgroundBlurView, context _: Context) {}
}

open class BackgroundBlurView: UIVisualEffectView {
    private let keyPath = "filters.gaussianBlur.inputRadius"

    public var blurRadius: CGFloat {
        get { blurLayer?.value(forKeyPath: keyPath) as? CGFloat ?? 0 }
        set { blurLayer?.setValue(newValue as NSNumber, forKeyPath: keyPath) }
    }

    private weak var blurLayer: CALayer?

    public init(radius: CGFloat) {
        super.init(effect: UIBlurEffect(style: .regular))
        for subview in subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        if let sublayer = layer.sublayers?.first, let filters = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            sublayer.filters = filters.filter { "\($0)" == "gaussianBlur" }
            self.blurLayer = sublayer
        }
        self.blurRadius = radius
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func traitCollectionDidChange(_: UITraitCollection?) {
        // prevent effects reenabling
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    HStack(spacing: 0) {
        Color.blue
        Color.blue.opacity(0.2)
    }
    .overlay {
        BackgroundBlur(radius: 50)
            .frame(width: 200, height: 100)
            .clipShape(.capsule)
    }
    .ignoresSafeArea()
}
#endif
#endif
