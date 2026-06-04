//
//  ProfileButton.swift
//  cisum
//
//  Created by Aarav Gupta on 14/03/26.
//

import Kingfisher
import SwiftUI

public enum ProfileMenuAction {
    case profile
    case settings
    case plugins
}

public struct ProfileMenuCustomAction: Identifiable {
    public let id = UUID()
    public let title: String
    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

public struct ProfileButton: View {
    public var profileImageURL: URL?
    public var customActions: [ProfileMenuCustomAction]
    public var onAction: (ProfileMenuAction) -> Void
    
    @Environment(\.openURL) var openURL

    public init(profileImageURL: URL? = nil, customActions: [ProfileMenuCustomAction] = [], onAction: @escaping (ProfileMenuAction) -> Void) {
        self.profileImageURL = profileImageURL
        self.customActions = customActions
        self.onAction = onAction
    }

    #if os(iOS)
    @State var isClicked: Bool = false
    #elseif os(macOS)
    @State var isClicked: Bool = true
    #endif
    @State private var isHovering: Bool = false
    @Namespace private var namespace

    private enum Layout {
        static let collapsedSize: CGFloat = 60
        static let expandedWidth: CGFloat = 175
        static let expandedProfileSize: CGFloat = 50
        static let menuCornerRadius: CGFloat = 50
        static let menuHeight: CGFloat = 50
        static let hoverScale: CGFloat = 1.01
    }

    private var expandedShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 40,
            bottomLeadingRadius: 35,
            bottomTrailingRadius: 35,
            topTrailingRadius: 40,
            style: .continuous
        )
    }

    private var toggleAnimation: Animation {
        #if os(iOS)
        return .smooth(duration: 0.3)
        #else
        return .smooth(duration: 0.32)
        #endif
    }

    private var hoverAnimation: Animation {
        .smooth(duration: 0.2)
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            #if os(iOS)
            if isClicked {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeMenu()
                    }
            }
            #endif
            menuSurface
                .onTapGesture {
                    toggleMenu()
                }
        }
        #if os(macOS)
        .onHover { isHovering in
            withAnimation(hoverAnimation) {
                self.isHovering = isHovering
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        #endif
        .onDisappear {
            isClicked = false
            isHovering = false
        }
    }

    @ViewBuilder
    private var menuSurface: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if isExpanded {
                expandedGlass
            } else {
                collapsedGlass
            }
        } else {
            if isExpanded {
                fallbackExpandedGlass
            } else {
                fallbackCollapsedGlass
            }
        }
    }

    private var isExpanded: Bool {
        #if os(iOS)
        isClicked
        #else
        isClicked && isHovering
        #endif
    }

    private func toggleMenu() {
        withAnimation(toggleAnimation) {
            isClicked.toggle()
        }
    }

    private func closeMenu() {
        guard isClicked else { return }
        withAnimation(toggleAnimation) {
            isClicked = false
        }
    }

    private var collapsedOverlayContent: some View {
        ZStack {
            Color.clear
                .matchedGeometryEffect(id: "USERNAME", in: namespace)
                .frame(width: 1, height: 1)
                .offset(x: -10)

            Color.clear
                .matchedGeometryEffect(id: "PROFILE_BUTTONS", in: namespace)
                .frame(width: 1, height: 1)
                .offset(y: 80)

            if let url = profileImageURL {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(Color.cisumChromeSubtle)
                    }
                    .resizable()
                    .matchedGeometryEffect(id: "PROFILE", in: namespace)
                    .clipShape(.circle)
                    .frame(width: Layout.collapsedSize - 10, height: Layout.collapsedSize - 10)
                    .animation(.easeInOut(duration: 0.25), value: isExpanded)
            } else {
                Circle()
                    .fill(Color.cisumChromeSubtle)
                    .padding(5)
                    .matchedGeometryEffect(id: "PROFILE", in: namespace)
                    .animation(.easeInOut(duration: 0.25), value: isExpanded)
            }
        }
    }

    private var expandedOverlayContent: some View {
        VStack {
            HStack {
                #if os(iOS)
                Button {
                    onAction(.profile)
                } label: {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 50)
                            .fill(.clear)
                            .glassEffect(.regular)
                            .overlay {
                                Text("Profile")
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                    } else {
                        // Fallback on earlier versions
                        RoundedRectangle(cornerRadius: Layout.menuCornerRadius)
                            .stroke(Color.cisumChromeSubtle, lineWidth: 1.5)
                            .foregroundStyle(.ultraThinMaterial)
                            .overlay {
                                Text("Profile")
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                    }
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "USERNAME", in: namespace, anchor: .topTrailing)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.expandedProfileSize)

                if let url = profileImageURL {
                    KFImage(url)
                        .placeholder {
                            Circle()
                                .fill(Color.cisumChromeSubtle)
                        }
                        .resizable()
                        .matchedGeometryEffect(id: "PROFILE", in: namespace)
                        .clipShape(.circle)
                        .frame(
                            width: Layout.expandedProfileSize,
                            height: Layout.expandedProfileSize
                        )
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                } else {
                    Circle()
                        .fill(Color.cisumChromeSubtle)
                        .matchedGeometryEffect(id: "PROFILE", in: namespace)
                        .frame(
                            width: Layout.expandedProfileSize,
                            height: Layout.expandedProfileSize
                        )
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                }

                #elseif os(macOS)
                if let url = profileImageURL {
                    KFImage(url)
                        .placeholder {
                            Circle()
                                .fill(Color.cisumChromeSubtle)
                        }
                        .matchedGeometryEffect(id: "PROFILE", in: namespace)
                        .frame(width: Layout.collapsedSize, height: Layout.collapsedSize)
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                } else {
                    Circle()
                        .fill(Color.cisumChromeSubtle)
                        .matchedGeometryEffect(id: "PROFILE", in: namespace)
                        .frame(width: Layout.collapsedSize, height: Layout.collapsedSize)
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)
                }

                Spacer()
                #endif
            }
            .padding([.top, .horizontal], 10)

            VStack {
                if #available(macOS 26.0, iOS 26.0, *) {
                    #if os(macOS)
                    Button {
                        onAction(.profile)
                    } label: {
                        RoundedRectangle(cornerRadius: 50)
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: Layout.menuCornerRadius))
                            .contentShape(.rect(cornerRadius: Layout.menuCornerRadius))
                            .padding(.horizontal, 10)
                            .frame(height: Layout.menuHeight)
                            .overlay {
                                Text("Profile")
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(id: "USERNAME", in: namespace, anchor: .topTrailing)
                    #endif

                    Button {
                        onAction(.settings)
                    } label: {
                        menuRowGlassModern
                            .overlay {
                                Text("Settings")
                            }
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAction(.plugins)
                    } label: {
                        menuRowGlassModern
                            .overlay {
                                Text("Plugins")
                            }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        openURL(URL(string: "https://discord.com/invite/Mb4F9Gmuex")!)
                    } label: {
                        menuRowGlassModern
                            .overlay {
                                Text("Support")
                            }
                    }
                    .buttonStyle(.plain)

                    if !customActions.isEmpty {
                        Rectangle()
                            .fill(Color.cisumChromeStrong)
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)

                        ForEach(customActions) { customAction in
                            Button {
                                customAction.action()
                                closeMenu()
                            } label: {
                                menuRowGlassModern
                                    .overlay {
                                        Text(customAction.title)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button {
                        onAction(.settings)
                    } label: {
                        menuRowGlassFallback
                            .overlay {
                                Text("Settings")
                            }
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAction(.plugins)
                    } label: {
                        menuRowGlassFallback
                            .overlay {
                                Text("Plugins")
                            }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        openURL(URL(string: "https://discord.com/invite/Mb4F9Gmuex")!)
                    } label: {
                        menuRowGlassFallback
                            .overlay {
                                Text("Support")
                            }
                    }
                    .buttonStyle(.plain)

                    if !customActions.isEmpty {
                        Rectangle()
                            .fill(Color.cisumChromeStrong)
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)

                        ForEach(customActions) { customAction in
                            Button {
                                customAction.action()
                                closeMenu()
                            } label: {
                                menuRowGlassFallback
                                    .overlay {
                                        Text(customAction.title)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .matchedGeometryEffect(id: "PROFILE_BUTTONS", in: namespace)
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @available(macOS 26.0, iOS 26.0, *)
    private var collapsedGlass: some View {
        collapsedOverlayContent
            .frame(width: Layout.collapsedSize, height: Layout.collapsedSize)
            .background {
                Circle()
                    .glassEffect(.regular, in: .circle)
                    .matchedGeometryEffect(id: "GLASS", in: namespace)
            }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private var expandedGlass: some View {
        expandedOverlayContent
            .frame(width: Layout.expandedWidth)
            .background {
                expandedShape
                    .glassEffect(.regular, in: expandedShape)
                    .matchedGeometryEffect(id: "GLASS", in: namespace)
            }
    }

    private var fallbackCollapsedGlass: some View {
        collapsedOverlayContent
            .frame(width: Layout.collapsedSize, height: Layout.collapsedSize)
            .background {
                Circle()
                    .stroke(Color.cisumChromeBorder, lineWidth: 2)
                    .fill(.ultraThinMaterial)
                    .matchedGeometryEffect(id: "GLASS", in: namespace)
            }
    }

    private var fallbackExpandedGlass: some View {
        expandedOverlayContent
            .frame(width: Layout.expandedWidth)
            .background {
                expandedShape
                    .stroke(Color.cisumChromeBorder, lineWidth: 3)
                    .fill(.ultraThinMaterial)
                    .matchedGeometryEffect(id: "GLASS", in: namespace)
            }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private var menuRowGlassModern: some View {
        RoundedRectangle(cornerRadius: Layout.menuCornerRadius)
            .fill(.clear)
            .glassEffect(.regular, in: .rect(cornerRadius: Layout.menuCornerRadius))
            .contentShape(.rect(cornerRadius: Layout.menuCornerRadius))
            .padding(.horizontal, 10)
            .frame(height: Layout.menuHeight)
    }

    private var menuRowGlassFallback: some View {
        RoundedRectangle(cornerRadius: Layout.menuCornerRadius)
            .stroke(Color.cisumChromeSubtle, lineWidth: 1.5)
            .foregroundStyle(.ultraThinMaterial)
            .padding(.horizontal, 10)
            .frame(height: Layout.menuHeight)
    }
}

#Preview {
    ProfileButton(profileImageURL: nil, onAction: { _ in })
        .preferredColorScheme(.dark)
}
