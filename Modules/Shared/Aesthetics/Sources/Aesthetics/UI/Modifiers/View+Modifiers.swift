//
//  View+Modifiers.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

import SwiftUI

public extension View {
    func tabbarBottomViewAccessory(content: () -> some View) -> some View {
        environment(\.tabBarBottomAccessory, AnyView(content()))
    }

    func tabbarVisibility(_ visibility: Visibility) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return environment(\.tabBarVisibility, visibility)
                .toolbarVisibility(visibility, for: .tabBar)
        } else {
            return environment(\.tabBarVisibility, visibility)
        }
        #else
        return environment(\.tabBarVisibility, visibility)
        #endif
    }
}

public extension View {
    func onScrollPhaseUpdate(
        action: @escaping (ScrollPhases, ScrollPhases) -> Void
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return onScrollPhaseChange { oldPhase, newPhase in
                action(ScrollPhases(oldPhase), ScrollPhases(newPhase))
            }
        } else {
            return modifier(ScrollPhaseUpdateModifier(action: action))
        }
        #else
        return self
        #endif
    }

    func onScrollOffsetChange(
        action: @escaping (CGFloat, CGFloat) -> Void
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return onScrollGeometryChange(
                for: CGFloat.self,
                of: { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                },
                action: action
            )
        } else {
            return modifier(
                ScrollOffsetChangeModifier(
                    transform: { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    },
                    action: action
                )
            )
        }
        #else
        return self
        #endif
    }
}
