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
    @Environment(\.openURL) var openURL
    public var profileImageURL: URL?
    public var customActions: [ProfileMenuCustomAction]
    public var onAction: (ProfileMenuAction) -> Void

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

    /// One shape for both states, so the glass animates its radii instead of swapping shape types.
    /// Collapsed, every radius is half the side: a circle.
    private var surfaceShape: UnevenRoundedRectangle {
        let collapsed = Layout.collapsedSize / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: isExpanded ? 40 : collapsed,
            bottomLeadingRadius: isExpanded ? 35 : collapsed,
            bottomTrailingRadius: isExpanded ? 35 : collapsed,
            topTrailingRadius: isExpanded ? 40 : collapsed,
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
        menuSurface
            .onTapGesture {
                toggleMenu()
            }
            #if os(iOS)
            // Behind the surface and far larger than it, so a tap anywhere else on screen closes the
            // menu. It used to be a sibling in this view's own ZStack, which is only as big as the
            // button — taps outside it fell through to whatever was underneath.
            // ponytail: oversized catcher rather than hoisting it to the screen root.
            .background {
                if isClicked {
                    Color.clear
                        .frame(width: 4000, height: 4000)
                        .contentShape(Rectangle())
                        .onTapGesture { closeMenu() }
                }
            }
            #endif
            #if os(macOS)
            .onHover { isHovering in
                withAnimation(hoverAnimation) {
                    self.isHovering = isHovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
            .onDisappear {
                isClicked = false
                isHovering = false
            }
    }

    /// One surface in both states. The glass stays put and only its frame and radii animate; the
    /// contents cross-fade inside it, and the avatar is the one element that travels.
    private var menuSurface: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedOverlayContent
                    .transition(.opacity)
            } else {
                collapsedOverlayContent
                    .transition(.opacity)
            }
        }
        .frame(
            width: isExpanded ? Layout.expandedWidth : Layout.collapsedSize,
            height: isExpanded ? nil : Layout.collapsedSize,
            alignment: .top
        )
        // The rows are laid out full-size from the first frame; clipped to the growing glass they
        // are revealed by it instead of hanging outside it while it is still small.
        .clipShape(surfaceShape)
        .background { glass }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // Clear first: an unfilled shape is painted in the inherited text colour.
            surfaceShape
                .fill(.clear)
                .glassEffect(.regular, in: surfaceShape)
        } else {
            surfaceShape
                .fill(.ultraThinMaterial)
                .overlay { surfaceShape.stroke(Color.cisumChromeBorder, lineWidth: isExpanded ? 3 : 2) }
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

    /// Every menu row closes the menu; only the custom actions used to.
    private func choose(_ action: ProfileMenuAction) {
        closeMenu()
        onAction(action)
    }

    private func openSupport() {
        closeMenu()
        openURL(URL(string: "https://discord.com/invite/Mb4F9Gmuex")!)
    }

    /// The avatar, the one view matched between the two states.
    ///
    /// `matchedGeometryEffect` comes last: it matches the geometry of the view it is applied to, so
    /// placed before `.frame` it matched the unframed image and the two ends disagreed. No
    /// `.animation` of its own either — it rides the toggle's animation, so it lands with the glass.
    private func avatar(size: CGFloat) -> some View {
        Group {
            if let url = profileImageURL {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(Color.cisumChromeSubtle)
                    }
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.cisumChromeSubtle)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .matchedGeometryEffect(id: "PROFILE", in: namespace)
    }

    private var collapsedOverlayContent: some View {
        avatar(size: Layout.collapsedSize - 10)
            .frame(width: Layout.collapsedSize, height: Layout.collapsedSize)
    }

    // The rows are not matched to anything. Matching the whole stack to the collapsed circle laid it
    // out 60 pt wide mid-animation, so every label wrapped a letter at a time; they now fade in
    // place while the glass grows around them.
    private var expandedOverlayContent: some View {
        VStack {
            HStack {
                #if os(iOS)
                Button {
                    choose(.profile)
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
                .frame(maxWidth: .infinity)
                .frame(height: Layout.expandedProfileSize)

                avatar(size: Layout.expandedProfileSize)

                #elseif os(macOS)
                avatar(size: Layout.collapsedSize)

                Spacer()
                #endif
            }
            .padding([.top, .horizontal], 10)

            VStack {
                #if os(macOS)
                if #available(macOS 26.0, *) {
                    Button {
                        choose(.profile)
                    } label: {
                        menuRow("Profile")
                    }
                    .buttonStyle(.plain)
                }
                #endif

                Button {
                    choose(.settings)
                } label: {
                    menuRow("Settings")
                }
                .buttonStyle(.plain)

                Button {
                    choose(.plugins)
                } label: {
                    menuRow("Plugins")
                }
                .buttonStyle(.plain)

                Button {
                    openSupport()
                } label: {
                    menuRow("Support")
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
                            menuRow(customAction.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func menuRow(_ title: String) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: Layout.menuCornerRadius)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: Layout.menuCornerRadius))
                .contentShape(.rect(cornerRadius: Layout.menuCornerRadius))
                .padding(.horizontal, 10)
                .frame(height: Layout.menuHeight)
                .overlay { Text(title) }
        } else {
            RoundedRectangle(cornerRadius: Layout.menuCornerRadius)
                .stroke(Color.cisumChromeSubtle, lineWidth: 1.5)
                .foregroundStyle(.ultraThinMaterial)
                .padding(.horizontal, 10)
                .frame(height: Layout.menuHeight)
                .overlay { Text(title) }
        }
    }
}

#Preview {
    ProfileButton(profileImageURL: nil, onAction: { _ in })
        .preferredColorScheme(.dark)
}
