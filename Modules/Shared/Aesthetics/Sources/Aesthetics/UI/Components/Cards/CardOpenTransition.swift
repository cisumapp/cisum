import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CardOpenTransition<Hero: View, Content: View>: View {
    var config: TransitionConfig = .init()
    var backgroundColor: Color?
    @ViewBuilder public var hero: (_ isCardExpanded: Bool, _ dismiss: (() -> Void)?) -> Hero
    @ViewBuilder public var content: (_ safeArea: EdgeInsets, _ dismiss: @escaping () -> Void) -> Content
    @State private var showFullScreenCover: Bool = false
    @State private var sourceRect: CGRect = .zero
    @State private var buttonScale: CGFloat = 1

    public init(
        backgroundColor: Color? = nil,
        @ViewBuilder hero: @escaping (_ isCardExpanded: Bool, _ dismiss: (() -> Void)?) -> Hero,
        @ViewBuilder content: @escaping (_ safeArea: EdgeInsets, _ dismiss: @escaping () -> Void) -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.hero = hero
        self.content = content
    }

    public var body: some View {
        Button {
            withoutAnimation {
                showFullScreenCover = true
            }
        } label: {
            Rectangle()
                .foregroundStyle(.clear)
                .overlay {
                    if !showFullScreenCover {
                        hero(false, nil)
                    }
                }
                .onGeometryChange(for: CGRect.self, of: { geo in
                    geo.frame(in: .global)
                }, action: { newValue in
                    buttonScale = sourceRect.width > 0 ? newValue.width / sourceRect.width : 1
                })
        }
        .buttonStyle(CardStyle())
        .onGeometryChange(for: CGRect.self, of: { geo in
            geo.frame(in: .global)
        }, action: { newValue in
            sourceRect = newValue
        })
        #if os(iOS)
        // Under the tab bar and its accessory, and added and removed in one frame: the cover
        // animates its own open and close, and an overlay fade on top of that left a
        // full-screen copy lingering over the card after it had closed.
        .universalOverlay(animation: nil, layer: .tab, show: $showFullScreenCover) {
            TransitionFullScreenCover(
                config: config,
                backgroundColor: backgroundColor,
                buttonScale: $buttonScale,
                showFullScreenCover: $showFullScreenCover,
                sourceRect: $sourceRect,
                hero: hero,
                content: content
            )
        }
        #endif
    }
}

private struct TransitionFullScreenCover<Hero: View, Content: View>: View {
    var config: TransitionConfig
    var backgroundColor: Color?
    @Binding var buttonScale: CGFloat
    @Binding var showFullScreenCover: Bool
    @Binding var sourceRect: CGRect
    @ViewBuilder var hero: (_ isCardExpanded: Bool, _ dismiss: (() -> Void)?) -> Hero
    @ViewBuilder var content: (_ safeArea: EdgeInsets, _ dismiss: @escaping () -> Void) -> Content

    @State private var animateContents: Bool = false
    @State private var isDismissing = false
    @State private var dragScale: CGFloat = 1
    @State private var safeArea: EdgeInsets = .init()

    #if os(iOS)
    @State private var isHorizontalSwipe: Bool = false
    #endif

    var body: some View {
        let cornerRadius = animateContents ? config.detailCornerRadius : config.cardCornerRadius

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Rectangle()
                    .foregroundStyle(.clear)
                    .overlay { hero(animateContents, dismiss) }
                    .frame(
                        width: animateContents ? nil : sourceRect.width,
                        height: animateContents ? config.detailCardHeight : sourceRect.height
                    )
                    .offset(
                        x: animateContents ? 0 : sourceRect.minX,
                        y: animateContents ? 0 : sourceRect.minY
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .visualEffect { [animateContents] content, proxy in
                        let minY = proxy.frame(in: .scrollView).minY
                        let height = animateContents ? (proxy.size.height + 10) : 0

                        return content
                            .offset(y: -minY > height ? -(minY + height) : 0)
                            .offset(y: minY > 0 ? -minY : 0)
                    }
                    .zIndex(1000)

                // Faded with the expansion: while the card collapses, the list under the hero
                // otherwise shows through the shrinking mask wherever the cover is not opaque.
                content(safeArea, dismiss)
                    .opacity(animateContents ? 1 : 0)
            }
        }
        .background {
            Group {
                if let backgroundColor {
                    backgroundColor
                } else {
                    Color.clear.background(.background)
                }
            }
            // Faded with the collapse, so the mask's margin below never shows as a border.
            .opacity(animateContents ? 1 : 0)
        }
        // Collapsed, the mask keeps a margin around the card: a hero can draw past its own
        // frame (the playlist cover's rotated stack of rectangles), and a mask cut to the card
        // clipped them away mid-close, so they popped back in only once the card was idle.
        .mask(alignment: .topLeading) {
            let bleed = animateContents ? 0 : sourceRect.width * 0.3
            RoundedRectangle(cornerRadius: cornerRadius - 1, style: .circular)
                .frame(
                    width: animateContents ? nil : sourceRect.width + bleed * 2,
                    height: animateContents ? nil : sourceRect.height + bleed * 2
                )
                .offset(
                    x: animateContents ? 0 : sourceRect.minX - bleed,
                    y: animateContents ? 0 : sourceRect.minY - bleed
                )
        }
        .overlay(alignment: .topLeading) {
            dismissButton()
                .hidden()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .frame(
                    width: animateContents ? nil : sourceRect.width,
                    height: animateContents ? config.detailCardHeight : sourceRect.height
                )
                .offset(
                    x: animateContents ? 0 : sourceRect.minX,
                    y: animateContents ? safeArea.top : sourceRect.minY
                )
        }
        // The cover is drawn by an overlay host, outside the card's own environment, so the
        // surface under its text is declared here: the card's colour.
        .legibilityBackground(backgroundColor ?? .cisumBg)
        .scaleEffect(dragScale)
        .scaleEffect(buttonScale)
        .ignoresSafeArea()
        #if os(iOS)
            .gesture(
                CardGesture { gesture in
                    handleGesture(gesture)
                }
            )
        #endif
            .onGeometryChange(for: EdgeInsets.self) { geo in
                geo.safeAreaInsets
            } action: { newValue in
                safeArea = newValue
            }
            .task {
                guard !animateContents else { return }

                withAnimation(config.animation) {
                    animateContents = true
                }
            }
            .presentationBackground {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(animateContents ? 1 : 0)
            }
    }

    private func dismissButton() -> some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .frame(width: 20, height: 30)
                .contentShape(.circle)
        }
        .cardGlassButtonStyle()
        .padding(.trailing, 15)
        .animation(.linear(duration: 0.15)) {
            $0.opacity(animateContents ? 1 : 0)
        }
        .opacity((dragScale - 0.95) / 0.05)
    }

    #if os(iOS)
    private func handleGesture(_ gesture: UIPanGestureRecognizer) {
        let state = gesture.state
        let translationX = gesture.translation(in: gesture.view).x * 1.2
        let translationY = gesture.translation(in: gesture.view).y
        let translation = isHorizontalSwipe ? translationX : translationY

        if state == .began {
            isHorizontalSwipe = gesture.location(in: gesture.view).x < 60
        }

        if state == .began || state == .changed {
            let progress = max(min(translation / config.detailCardHeight, 1), 0)
            dragScale = 1 - (progress * 0.2)
        } else {
            isHorizontalSwipe = false

            if dragScale < 0.95 {
                dismiss()
            } else {
                withAnimation(config.animation) {
                    dragScale = 1
                }
            }
        }
    }
    #endif

    /// Collapses the card back into its source, then removes the cover.
    ///
    /// `.logicallyComplete` rather than `.removed`: a spring's last imperceptible wobble can run
    /// for a long time after it has visibly landed, and until then the full-screen cover stayed
    /// on top, invisible and swallowing taps. A second dismiss while one runs is ignored.
    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(config.animation, completionCriteria: .logicallyComplete) {
            dragScale = 1
            animateContents = false
        } completion: {
            withoutAnimation {
                showFullScreenCover = false
            }
        }
    }
}

fileprivate extension View {
    func withoutAnimation(block: @escaping () -> Void) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                block()
            }
        }
    }
}
