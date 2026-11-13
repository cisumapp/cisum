//
//  MediaComponents.swift
//  Aesthetics
//
//  The building blocks every page is made of, from the macOS artist design (Figma 86:5394):
//  section headers, song rows, cover tiles, shelves and the glass action pills.
//

import SwiftUI

// MARK: - Section header

/// "Title ›" over a section. With an action, the whole header opens the full list.
public struct MediaSectionHeader: View {
    let title: String
    let action: (() -> Void)?

    public init(_ title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { label(showsChevron: true) }
                .buttonStyle(MediaPressStyle())
        } else {
            label(showsChevron: false)
        }
    }

    private func label(showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary.opacity(0.9))
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

// MARK: - Song row

/// A song: 34pt artwork, title over "Album • Year", the duration, then Save and a menu.
///
/// Highlights under the pointer and on press; the row itself plays the song.
public struct MediaSongRow<Menu: View>: View {
    let title: String
    let subtitle: String
    let duration: String?
    let artworkURL: URL?
    let isExplicit: Bool
    let isSaved: Bool?
    let onPlay: () -> Void
    let onToggleSave: (() -> Void)?
    @ViewBuilder let menu: Menu

    @State private var isHovering = false

    /// - Parameters:
    ///   - isSaved: `nil` hides the star.
    ///   - menu: the "…" menu's items; an `EmptyView` hides it.
    public init(
        title: String,
        subtitle: String,
        duration: String? = nil,
        artworkURL: URL?,
        isExplicit: Bool = false,
        isSaved: Bool? = nil,
        onPlay: @escaping () -> Void,
        onToggleSave: (() -> Void)? = nil,
        @ViewBuilder menu: () -> Menu
    ) {
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
        self.isSaved = isSaved
        self.onPlay = onPlay
        self.onToggleSave = onToggleSave
        self.menu = menu()
    }

    public var body: some View {
        HStack(spacing: 30) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    MediaArtwork(url: artworkURL, cornerRadius: 6)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.8))
                        if isExplicit || !subtitle.isEmpty {
                            HStack(spacing: 4) {
                                if isExplicit { ExplicitBadge() }
                                Text(subtitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 16)
                    if let duration {
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack(spacing: 15) {
                if let isSaved, let onToggleSave {
                    Button(action: onToggleSave) {
                        Image(systemName: isSaved ? "star.fill" : "star")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(MediaPressStyle())
                    .accessibilityLabel(isSaved ? "Remove from Saved" : "Save")
                }
                if !(Menu.self == EmptyView.self) {
                    SwiftUI.Menu {
                        menu
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 20, height: 20)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden)
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.fillSubtle : .clear)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

public extension MediaSongRow where Menu == EmptyView {
    init(
        title: String,
        subtitle: String,
        duration: String? = nil,
        artworkURL: URL?,
        isExplicit: Bool = false,
        isSaved: Bool? = nil,
        onPlay: @escaping () -> Void,
        onToggleSave: (() -> Void)? = nil
    ) {
        self.init(
            title: title, subtitle: subtitle, duration: duration, artworkURL: artworkURL,
            isExplicit: isExplicit, isSaved: isSaved, onPlay: onPlay, onToggleSave: onToggleSave
        ) { EmptyView() }
    }
}

/// The "E" shown beside a song the source marked explicit. One view so every list says it the same
/// way — and says it to VoiceOver, which the bare symbol did not.
public struct ExplicitBadge: View {
    public init() {}

    public var body: some View {
        Image(systemName: "e.square.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
    }
}

// MARK: - Tiles

/// The shapes a cover takes: albums and playlists are square, videos wide, artists round.
public enum MediaTileShape: Sendable {
    case square, wide, round

    var size: CGSize {
        switch self {
        case .square, .round: CGSize(width: 160, height: 160)
        case .wide: CGSize(width: 284, height: 160)
        }
    }
}

/// A cover with its title and subtitle under it. Lifts slightly under the pointer.
public struct MediaTile: View {
    let url: URL?
    let title: String
    let subtitle: String?
    let shape: MediaTileShape
    let action: () -> Void

    @State private var isHovering = false

    public init(url: URL?, title: String, subtitle: String? = nil, shape: MediaTileShape = .square, action: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.shape = shape
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: shape == .round ? .center : .leading, spacing: 7) {
                MediaArtwork(url: url, cornerRadius: shape == .round ? shape.size.width / 2 : 8)
                    .frame(width: shape.size.width, height: shape.size.height)
                    .scaleEffect(isHovering ? 1.03 : 1)
                    .shadow(color: .black.opacity(isHovering ? 0.3 : 0), radius: 10, y: 6)

                VStack(alignment: shape == .round ? .center : .leading, spacing: 0) {
                    // The page's ink, not the system's: tiles sit on palette-coloured pages.
                    Text(title)
                        .legibleForeground(.primary)
                        .lineLimit(shape == .round ? 1 : 2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .legibleForeground(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(shape == .round ? .center : .leading)
            }
            .frame(width: shape.size.width, alignment: shape == .round ? .center : .leading)
            .contentShape(.rect)
        }
        .buttonStyle(MediaPressStyle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 1)) { isHovering = hovering }
        }
    }
}

/// A horizontal row of tiles that scrolls past the edge.
public struct MediaShelf<Content: View>: View {
    @ViewBuilder let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 26) {
                content
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Artwork

/// Remote artwork with a quiet placeholder, at any corner radius.
public struct MediaArtwork: View {
    let url: URL?
    let cornerRadius: CGFloat

    public init(url: URL?, cornerRadius: CGFloat = 8) {
        self.url = url
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Color.fillSubtle
            .overlay {
                if let url {
                    ArtworkImage(url: url, size: 320)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Glass pills

/// A capsule of glass holding a few controls, like the design's action pills.
public struct GlassPill<Content: View>: View {
    @ViewBuilder let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background {
            let shape = Capsule(style: .continuous)
            Group {
                #if os(macOS)
                if #available(macOS 26.0, *) {
                    shape.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
                #else
                if #available(iOS 26.0, *) {
                    shape.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
                #endif
            }
            .overlay { shape.fill(Color.cisumBg.opacity(0.4)) }
            .overlay { shape.strokeBorder(Color.cisumChromeSubtle, lineWidth: 1) }
            .shadow(color: .black.opacity(0.3), radius: 2.5, y: 3)
        }
    }
}

/// "▶ Play | shuffle" — the primary action pill on artist, album and playlist pages.
public struct PlayShufflePill: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    public init(onPlay: @escaping () -> Void, onShuffle: @escaping () -> Void) {
        self.onPlay = onPlay
        self.onShuffle = onShuffle
    }

    public var body: some View {
        GlassPill {
            Button(action: onPlay) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Play").foregroundStyle(.primary.opacity(0.9))
                }
                .contentShape(.rect)
            }
            .buttonStyle(MediaPressStyle())

            Rectangle()
                .fill(Color.cisumChromeSubtle)
                .frame(width: 1, height: 15)

            Button(action: onShuffle) {
                Image(systemName: "shuffle")
                    .frame(width: 20, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(MediaPressStyle())
            .accessibilityLabel("Shuffle")
        }
    }
}

// MARK: - Press feedback

/// Dips slightly while pressed, so a click is felt the moment it lands.
public struct MediaPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 1), value: configuration.isPressed)
    }
}
