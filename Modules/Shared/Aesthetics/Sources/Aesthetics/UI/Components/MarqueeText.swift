//
//  MarqueeText.swift
//  Aesthetics
//
//  Adapted from AppleMusicStylePlayer by Alexey Vorobyov.
//  https://github.com/f728743/AppleMusicStylePlayer
//
//  MIT License — Copyright (c) 2025 Alexey Vorobyov
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software
//  and associated documentation files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or
//  substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
//  BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import SwiftUI

/// Text that scrolls horizontally when it does not fit, and sits still when it does.
///
/// Two copies of the string are offset one line-width apart and animated continuously, so the
/// scroll wraps seamlessly rather than snapping back. A fade mask at each edge hides the seam.
///
/// The measurement happens in a hidden overlay of the same text, because the visible copies are
/// already offset and clipped and so cannot report their natural width.
public struct MarqueeText: View {
    public let text: String
    private let config: Config

    @State private var textSize: CGSize = .zero
    @State private var animate = false

    public init(_ text: String, config: Config = .init()) {
        self.text = text
        self.config = config
    }

    public var body: some View {
        GeometryReader { geo in
            let viewWidth = geo.size.width
            // Only scroll when the text genuinely overflows; otherwise a short title would drift
            // for no reason.
            let scrolls = textSize.width > viewWidth

            ZStack {
                animatedText(viewWidth: viewWidth)
                    .opacity(scrolls ? 1 : 0)

                staticText
                    .opacity(scrolls ? 0 : 1)
            }
        }
        .frame(height: textSize.height)
        .overlay {
            // Hidden measuring copy: unclipped and unoffset, so its width is the real one.
            Text(text)
                .padding(.leading, config.leftFade)
                .padding(.trailing, config.rightFade)
                .lineLimit(1)
                .fixedSize()
                .measureSize { textSize = $0 }
                .hidden()
        }
        .onAppear {
            withAnimation(animation) {
                animate = true
            }
        }
    }

    public struct Config: Sendable {
        public var startDelay: Double
        public var alignment: Alignment
        public var leftFade: CGFloat
        public var rightFade: CGFloat
        public var spacing: CGFloat

        public init(
            startDelay: Double = 1.0,
            alignment: Alignment = .leading,
            leftFade: CGFloat = 40,
            rightFade: CGFloat = 40,
            spacing: CGFloat = 100
        ) {
            self.startDelay = startDelay
            self.alignment = alignment
            self.leftFade = leftFade
            self.rightFade = rightFade
            self.spacing = spacing
        }
    }
}

private extension MarqueeText {
    func animatedText(viewWidth: CGFloat) -> some View {
        Group {
            Text(text)
                .offset(x: -offset)
            Text(text)
                .offset(x: -offset + lineWidth)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(width: viewWidth)
        .offset(x: config.leftFade)
        .mask(fadeMask)
    }

    /// Distance the text travels before the second copy lands exactly where the first started.
    var lineWidth: CGFloat {
        textSize.width - (config.leftFade + config.rightFade) + config.spacing
    }

    var offset: Double {
        animate ? lineWidth : 0
    }

    var staticText: some View {
        Text(text)
            .padding(.leading, config.leftFade)
            .padding(.trailing, config.rightFade)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: config.alignment)
    }

    /// Speed is proportional to length, so long and short titles scroll at the same rate rather
    /// than taking the same time.
    var animation: Animation {
        .linear(duration: Double(textSize.width) / 30)
            .delay(config.startDelay)
            .repeatForever(autoreverses: false)
    }

    var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0), .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: config.leftFade)

            Color.black

            LinearGradient(
                colors: [.black, .black.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: config.rightFade)
        }
        .padding(.horizontal, 6)
    }
}

public extension View {
    /// Reports this view's size as it changes.
    ///
    /// Built on the `SizePreferenceKey` already in this module rather than importing a second,
    /// identical one alongside `MarqueeText`.
    func measureSize(perform action: @escaping (CGSize) -> Void) -> some View {
        overlay {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self) { size in
            Task { @MainActor in action(size) }
        }
    }
}

#Preview {
    HStack {
        MarqueeText(
            "A text that is way too long, but it scrolls",
            config: .init(startDelay: 3, leftFade: 32, rightFade: 32)
        )
        .background(.pink.opacity(0.6))

        Text("Normal Text")
            .background(.mint.opacity(0.6))
    }
    .padding(.horizontal, 16)
    .font(.largeTitle)
}
