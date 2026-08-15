//
//  ExpandablePlayer.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 10/05/25.
//

import Aesthetics
import SwiftUI
import Utilities

#if os(iOS)
public struct ExpandablePlayer: View {
    @Binding public var show: Bool
    @Binding public var isPlayerExpanded: Bool
    public var collapsedFrame: CGRect

    public init(show: Binding<Bool>, isPlayerExpanded: Binding<Bool>, collapsedFrame: CGRect) {
        self._show = show
        self._isPlayerExpanded = isPlayerExpanded
        self.collapsedFrame = collapsedFrame
    }

    public var body: some View {
        GeometryReader { proxy in
            ExpandablePlayerInner(
                size: proxy.size,
                safeArea: proxy.safeAreaInsets,
                show: $show,
                isPlayerExpanded: $isPlayerExpanded,
                collapsedFrame: collapsedFrame
            )
        }
    }
}

private struct ExpandablePlayerInner: View {
    var size: CGSize
    var safeArea: EdgeInsets

    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.isSearchExpanded) private var isSearchExpanded

    @Binding var show: Bool
    @Binding var isPlayerExpanded: Bool

    var collapsedFrame: CGRect

    var isSearchFieldExpanded: Bool {
        isSearchExpanded.wrappedValue
    }

    var isTabbarVisible: Bool {
        tabBarVisibility == .visible
    }

    // MARK: - Collapsed position helpers

    /// Offsets published by `iOSTabView`.
    ///
    /// The fallback derives from the same measured table rather than a separate set
    /// of magic numbers, so a device we have never run on still lands in the right
    /// place. It only applies before the first publish — this view lives in the
    /// detached overlay window, so `tabBarVisibility` / `isSearchExpanded` here are
    /// always their defaults and cannot be used to refine it.
    private var accessoryOffsets: ResponsiveLayout.AccessoryOffsets {
        TabBarStateStore.shared.accessoryOffsets
            ?? .init(
                state: .init(
                    orientation: size.width > size.height ? .landscape : .portrait,
                    placement: .inline,
                    searchActive: false
                ),
                screenWidth: size.width,
                safeAreaBottom: safeArea.bottom
            )
    }

    /// Places the pill exactly where the system accessory sits.
    private var collapsedBottomPadding: CGFloat {
        accessoryOffsets.bottomInsetFromScreenEdge
    }

    /// Horizontal padding in the collapsed state.
    private var collapsedHorizontalPadding: CGFloat {
        accessoryOffsets.sideInset
    }

    /// iOS 26: the measured platter height, so expansion starts exactly where the
    /// native accessory is. Nothing is visible at rest there, so this is an
    /// animation origin only.
    ///
    /// iOS 17/18: today's pill height — the overlay *is* the visible mini player on
    /// that path and its size must not change.
    private var collapsedHeight: CGFloat {
        if #available(iOS 26.0, *) {
            accessoryOffsets.accessoryHeight
        } else {
            Utilities.AppConstants.dynamicPlayerIslandHeight
        }
    }

    @Environment(PlayerThemeSettings.self) private var themeSettings

    @Namespace private var namespace

    @State private var offsetY: CGFloat = 0.0
    @State private var needRestoreProgressOnActive: Bool = false
    @State private var mainWindow: UIWindow?
    @State private var windowProgress: CGFloat = 0.0
    @State private var progressTrackState: CGFloat = 0.0
    @State private var expandProgress: CGFloat = 0.0

    var currentOrientation: UIDeviceOrientation = .portrait

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                playerContent(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(
                        .bottom,
                        isPlayerExpanded ? 0 : collapsedBottomPadding
                    )
                    .padding(
                        .horizontal,
                        isPlayerExpanded ? 0 : collapsedHorizontalPadding
                    )
                    .gesture(
                        PanGesture { newValue in
                            handleGestureChange(value: newValue, viewSize: size)
                        } onEnd: { newValue in
                            handleGestureEnd(value: newValue, viewSize: size)
                        }
                    )
                    .opacity(isFullyCollapsed ? 0 : 1)
                    .onChange(of: isPlayerExpanded) { _, expanded in
                        Aesthetics.PlayerExpansionState.shared.isExpanded = expanded
                        if expanded {
                            stacked(progress: 1, withAnimation: true)
                        } else {
                            resetStackedWithAnimation()
                        }
                    }
                    .onPreferenceChange(NowPlayingExpandProgressPreferenceKey.self) { value in
                        if expandProgress != value {
                            expandProgress = value
                        }
                    }
            } else {
                playerContent(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(
                        .bottom,
                        isPlayerExpanded ? 0 : collapsedBottomPadding
                    )
                    .padding(.horizontal, isPlayerExpanded ? 0 : collapsedHorizontalPadding)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard isPlayerExpanded else { return }
                                let translation = max(value.translation.height, 0)
                                offsetY = translation
                                windowProgress = max(min(translation / size.height, 1), 0) * 0.1

                                resizeWindow(0.1 - windowProgress)
                            }
                            .onEnded { value in
                                guard isPlayerExpanded else { return }
                                let translation = max(value.translation.height, 0)
                                let velocity = value.velocity.height / 5

                                withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                                    if (translation + velocity) > (size.height * 0.3) {
                                        // Closing View
                                        isPlayerExpanded = false
                                        // Resetting Window to identity with Animation
                                        resetWindowWithAnimation()
                                    } else {
                                        // Reset window to 0.1 with animation
                                        UIView.animate(withDuration: 0.3) {
                                            resizeWindow(0.1)
                                        }
                                    }

                                    offsetY = 0
                                }
                            }, including: isPlayerExpanded ? .all : .subviews
                    )
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        if isPlayerExpanded {
                            resetWindowToIdentity()
                        }
                    }
                    .onChange(of: isPlayerExpanded) { _, expanded in
                        Aesthetics.PlayerExpansionState.shared.isExpanded = expanded
                        if expanded {
                            applyExpandedWindowTransform()
                        } else {
                            resetWindowWithAnimation()
                        }
                    }
            }
        }
        .onAppear {
            Aesthetics.PlayerExpansionState.shared.isExpanded = isPlayerExpanded
            if let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow, mainWindow == nil {
                mainWindow = window
            }
        }
    }
}

private extension ExpandablePlayerInner {
    func applyExpandedWindowTransform() {
        UIView.animate(withDuration: Animation.playerExpandAnimationDuration) {
            resizeWindow(0.1)
        }
    }

    func resetWindowToIdentity() {
        mainWindow?.subviews.first?.transform = .identity
    }

    func resizeWindow(_ progress: CGFloat) {
        if let mainWindow = mainWindow?.subviews.first {
            let offsetY = (mainWindow.frame.height * progress) / 2

            // Corner Radius
            mainWindow.layer.cornerRadius = (progress / 0.1) * 30
            mainWindow.layer.masksToBounds = true
            mainWindow.transform = .identity.scaledBy(x: 1 - progress, y: 1 - progress).translatedBy(x: 0, y: offsetY)
        }
    }

    func resetWindowWithAnimation() {
        if let mainWindow = mainWindow?.subviews.first {
            UIView.animate(withDuration: 0.3) {
                mainWindow.layer.cornerRadius = 0
                mainWindow.transform = .identity
            }
        }
    }
}

private extension ExpandablePlayerInner {
    var isFullyExpanded: Bool {
        expandProgress >= 1
    }

    var isFullyCollapsed: Bool {
        expandProgress.isZero
    }

    func playerContent(size: CGSize) -> some View {
        // Only these three views vary by theme. Everything else in this file — the pan gesture,
        // stacked(), resizeWindow, offsetY, the collapsed geometry — is shared, so the player
        // opens and dismisses identically whichever theme is selected.
        let theme = themeSettings.selected

        return ZStack(alignment: .top) {
            PlayerThemeRenderer.background(
                theme,
                expanded: isPlayerExpanded,
                fullyExpanded: isFullyExpanded,
                collapsedHeight: collapsedHeight
            )

            // iOS 26 has a real .tabViewBottomAccessory acting as the collapsed
            // pill, so drawing a second one here is what produced the two-layer
            // handoff. iOS 17/18 has no native accessory — the overlay is the
            // only mini player there.
            if #unavailable(iOS 26.0) {
                PlayerThemeRenderer.miniPlayer(
                    theme,
                    expanded: $isPlayerExpanded,
                    namespace: namespace
                )
                .opacity(isPlayerExpanded ? 0 : 1)
            }

            PlayerThemeRenderer.expanded(
                theme,
                expanded: isPlayerExpanded,
                size: size,
                namespace: namespace
            )
            .opacity(isPlayerExpanded ? 1 : 0)

            ProgressTracker(progress: progressTrackState)
        }
        .frame(height: isPlayerExpanded ? nil : collapsedHeight, alignment: .top)
        .offset(y: offsetY)
        .ignoresSafeArea()
    }

    func handleGestureChange(value: PanGesture.Value, viewSize: CGSize) {
        guard isPlayerExpanded else { return }
        let translation = max(value.translation.height, 0)
        offsetY = translation
        windowProgress = max(min(translation / viewSize.height, 1), 0)
        stacked(progress: 1 - windowProgress, withAnimation: false)
    }

    func handleGestureEnd(value: PanGesture.Value, viewSize: CGSize) {
        guard isPlayerExpanded else { return }
        let translation = max(value.translation.height, 0)
        let velocity = value.velocity.height / 5
        withAnimation(.playerExpandAnimation) {
            if (translation + velocity) > (viewSize.height * 0.3) {
                isPlayerExpanded = false
                resetStackedWithAnimation()
            } else {
                stacked(progress: 1, withAnimation: true)
            }
            offsetY = 0
        }
    }

    func stacked(progress: CGFloat, withAnimation: Bool) {
        if withAnimation {
            SwiftUI.withAnimation(.playerExpandAnimation) {
                progressTrackState = progress
            }
        } else {
            progressTrackState = progress
        }
    }

    func resetStackedWithAnimation() {
        withAnimation(.playerExpandAnimation) {
            progressTrackState = 0
        }
    }
}

private struct ProgressTracker: View, @preconcurrency Animatable {
    var progress: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .preference(key: NowPlayingExpandProgressPreferenceKey.self, value: progress)
    }
}
#endif
