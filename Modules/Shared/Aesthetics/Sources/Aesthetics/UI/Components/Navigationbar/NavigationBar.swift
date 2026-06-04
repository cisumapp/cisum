//
//  NavigationBar.swift
//  cisum
//
//  Created by Aarav Gupta (github.com/atpugvaraa) on 18/03/25.
//

import SwiftUI
import Utilities

struct NavigationBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigationBarStyle) private var config
    @Environment(\.router) private var router
    @Environment(\.profileImageURL) private var profileImageURL

    var scrollOffset: CGFloat
    var title: String
    var icon: String?

    @State var showTopRightButton: Bool
    var customActions: [ProfileMenuCustomAction] = []

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: interpolation(start: 200, end: 130, transitionOffset: 60))
                .edgesIgnoringSafeArea(.top)

            navigationBar
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var navigationBar: some View {
        VStack {
            navigationTitle
                .overlay(alignment: .topTrailing) {
                    if showTopRightButton == true {
                        topRightButton()
                            .padding(.top, 6)
                            .padding(.trailing)
                    }
                }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9, blendDuration: 0.3), value: scrollOffset)
        .offset(y: interpolation(start: config.showSearchBar ? 10 : 10, end: config.showSearchBar ? -20 : 0, transitionOffset: 30))
    }

    var navigationTitle: some View {
        HStack {
            Text(title)
                .font(.system(size: interpolation(start: 35, end: 30, transitionOffset: 60)))
                .fontWeight(.bold)

            Spacer()
        }
        .padding()
    }

    func topRightButton() -> some View {
        ProfileButton(profileImageURL: profileImageURL, customActions: customActions, onAction: handleProfileAction)
            .scaleEffect(interpolation(start: 0.9, end: 0.857, transitionOffset: 60))
    }

    private func handleProfileAction(_ action: ProfileMenuAction) {
        switch action {
        case .profile:
            router.navigate(to: .profile)
        case .settings:
            router.navigate(to: .settings)
        case .plugins:
            router.navigate(to: .plugins)
        }
    }

    private func interpolation(start: CGFloat, end: CGFloat, transitionOffset: CGFloat) -> CGFloat {
        let progress = min(max(scrollOffset / transitionOffset, 0), 1)
        return end + (start - end) * progress
    }
}
