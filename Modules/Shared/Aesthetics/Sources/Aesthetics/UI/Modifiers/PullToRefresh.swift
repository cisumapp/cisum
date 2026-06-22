//
//  PullToRefresh.swift
//  Aesthetics
//
//  Created by Aarav Gupta on 13/06/26.
//

import SwiftUI

struct RefreshOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PullToRefresh: ViewModifier {
    var scrollOffset: CGFloat
    let action: () async -> Void
    
    // 1. Keep track of what's happening
    @State private var startingOffset: CGFloat? = nil
    @State private var isRefreshing: Bool = false
    @State private var hasReachedThreshold: Bool = false
    
    let threshold: CGFloat = 100
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .padding(.top)
                    .transition(.opacity)
            }
            
            content
                .offset(y: isRefreshing ? 40 : 0)
                .animation(.spring, value: isRefreshing)
//                .background(
//                    GeometryReader { geo in
//                        let offset = geo.frame(in: .global).minY
//                        Color.clear
//                            .preference(key: RefreshOffsetPreferenceKey.self, value: offset)
//                    }
//                )
        }
        .onChange(of: scrollOffset) { _, newOffset in
            handleOffsetChange(offset: newOffset)
        }
//        .onPreferenceChange(RefreshOffsetPreferenceKey.self) { offset in
//            handleOffsetChange(offset: offset)
//        }
    }
    
    private func handleOffsetChange(offset: CGFloat) {
        // Capture the baseline resting offset the first time this fires
        if startingOffset == nil {
            startingOffset = offset
        }
        
        guard let startingOffset = startingOffset, !isRefreshing else { return }
        
        // Calculate exactly how far they pulled DOWN from the resting position
        let pullDistance = offset - startingOffset
        
        // Now it works perfectly: it only triggers when they physically stretch it down!
        if pullDistance > threshold && !hasReachedThreshold {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            hasReachedThreshold = true
        }
        
        if pullDistance < threshold && hasReachedThreshold {
            hasReachedThreshold = false
            isRefreshing = true
            
            Task {
                await action()
                
                withAnimation {
                    isRefreshing = false
                }
            }
        }
    }
}

public extension View {
    func pullToRefresh(scrollOffset: CGFloat, action: @escaping () async -> Void) -> some View {
        self.modifier(PullToRefresh(scrollOffset: scrollOffset, action: action))
    }
}
