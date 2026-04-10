//
//  ExpandablePlayer.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 10/05/25.
//

import SwiftUI

struct ExpandablePlayer: View {
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    @Environment(\.isSearchExpanded) private var isSearchExpanded
    
    @Binding var show: Bool
    @Binding var isPlayerExpanded: Bool
    
    var isSearchFieldExpanded: Bool {
        return isSearchExpanded.wrappedValue
    }
    
    var isTabbarVisible: Bool {
        if tabBarVisibility == .visible {
            return true
        } else {
            return false
        }
    }
    
    var collapsedFrame: CGRect
    @Namespace private var namespace
    
    @State private var offsetY: CGFloat = 0.0
    @State private var needRestoreProgressOnActive: Bool = false
    @State private var mainWindow: UIWindow?
    @State private var windowProgress: CGFloat = 0.0
    @State private var progressTrackState: CGFloat = 0.0
    @State private var expandProgress: CGFloat = 0.0
    
    var currentOrientation: UIDeviceOrientation = .portrait
    
#if DEBUG
    @ObserveInjection var forceRedraw
#endif
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GeometryReader { proxy in
                    let size = proxy.size
                    let safeArea = proxy.safeAreaInsets
                    
                    playerContent(size: size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, isPlayerExpanded ? 0 : (isSearchFieldExpanded ? (isTabbarVisible ? safeArea.bottom + 18 : -12) : safeArea.bottom + 25))
                        .padding(.horizontal, isPlayerExpanded ? 0 : (isTabbarVisible ? 20 : (isSearchFieldExpanded ? 20 : 10)))
                        .gesture(
                            PanGesture { newValue in
                                handleGestureChange(value: newValue, viewSize: size)
                            } onEnd: { newValue in
                                handleGestureEnd(value: newValue, viewSize: size)
                            }
                        )
                }
                .opacity(isFullyCollapsed ? 0 : 1)
                .onChange(of: isPlayerExpanded) {
                    if isPlayerExpanded {
                        stacked(progress: 1, withAnimation: true)
                    }
                }
                .onPreferenceChange(NowPlayingExpandProgressPreferenceKey.self) { [$expandProgress] value in
                    if $expandProgress.wrappedValue != value {
                        $expandProgress.wrappedValue = value
                    }
                }
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    let safeArea = proxy.safeAreaInsets
                    
                    
                    playerContent(size: size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, isPlayerExpanded ? 0 : safeArea.bottom + (isSearchExpanded.wrappedValue ? 77 : 88))
                        .padding(.horizontal, isPlayerExpanded ? 0 : 20)
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
                                            /// Closing View
                                            isPlayerExpanded = false
                                            /// Resetting Window to identity with Animation
                                            resetWindowWithAnimation()
                                        } else {
                                            /// Reset window to 0.1 with animation
                                            UIView.animate(withDuration: 0.3) {
                                                resizeWindow(0.1)
                                            }
                                        }
                                        
                                        offsetY = 0
                                    }
                                }
                            ,including: isPlayerExpanded ? .all : .subviews)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    if isPlayerExpanded {
                        resetWindowToIdentity()
                    }
                }
                .onChange(of: isPlayerExpanded) { _, expanded in
                    if expanded {
                        applyExpandedWindowTransform()
                    } else {
                        resetWindowWithAnimation()
                    }
                }
//                .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
//                    #warning("Please fix this do not use dep injection")
//                    handleOrientationChange(UIDevice.current.orientation)
//                }
            }
        }
        .onAppear {
            if let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow, mainWindow == nil {
                mainWindow = window
            }
        }
        .enableInjection()
    }
}

private extension ExpandablePlayer {
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
            
            /// Corner Radius
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

private extension ExpandablePlayer {
    var isFullyExpanded: Bool {
        expandProgress >= 1
    }
    
    var isFullyCollapsed: Bool {
        expandProgress.isZero
    }
    
    func playerContent(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            PlayerBackground(
                isPlayerExpanded: isPlayerExpanded,
                isFullExpanded: isFullyExpanded
            )
            
            DynamicPlayerIsland(
                isPlayerExpanded: $isPlayerExpanded,
                namespace: namespace
            )
            .opacity(isPlayerExpanded ? 0 : 1)
            
            NowPlayingView(
                isPlayerExpanded: isPlayerExpanded,
                size: size,
                namespace: namespace
            )
            .opacity(isPlayerExpanded ? 1 : 0)
            
            ProgressTracker(progress: progressTrackState)
        }
        .frame(height: isPlayerExpanded ? nil : Constants.dynamicPlayerIslandHeight, alignment: .top)
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
    
    var insets: EdgeInsets {
        if isPlayerExpanded {
            return .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        return .init(
            top: 0,
            leading: collapsedFrame.minX,
            bottom: UIScreen.size.height - collapsedFrame.maxY,
            trailing: UIScreen.size.width - collapsedFrame.maxX
        )
    }
}

private struct ProgressTracker: View, @preconcurrency Animatable {
    var progress: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .preference(key: NowPlayingExpandProgressPreferenceKey.self, value: progress)
        .enableInjection()
    }
}

extension Animation {
    static let playerExpandAnimationDuration: TimeInterval = 0.3
    static var playerExpandAnimation: Animation {
        .smooth(duration: playerExpandAnimationDuration, extraBounce: 0)
    }
}
