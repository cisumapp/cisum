//
//  Vinyl.swift
//  cisum
//
//  Created by Aarav Gupta on 19/03/26.
//

import SwiftUI

struct VinylSideLabel {
    let title: String
    let subtitle: String?
}

public struct Vinyl<Content: View, Previous: View, UpNext: View>: View {
    let content: () -> Content
    let previous: (() -> Previous)?
    let upnext: (() -> UpNext)?
    let previousLabel: VinylSideLabel?
    let upnextLabel: VinylSideLabel?

    let isPlaying: Bool
    let accentColor: Color

    @State private var spin = VinylSpin()

    public var body: some View {
        GeometryReader { geo in
            let sizes = ResponsiveLayout.VinylSizes(screenWidth: geo.size.width)

            ZStack {
                VStack {
                    HStack {
                        ZStack(alignment: .topLeading) {
                            previousVinyl(size: sizes.sideDiskSize, offsetX: sizes.sideDiskOffsetPrevious)

                            if let previousLabel {
                                sideLabel(previousLabel, alignment: .leading)
                                    .padding(.leading, sizes.sideLabelInset)
                                    .padding(.top, sizes.sideLabelTopInset)
                            }
                        }
                        .frame(width: sizes.sideSlotWidth, height: sizes.sideSlotHeight)

                        Spacer(minLength: 0)

                        ZStack(alignment: .topTrailing) {
                            nextVinyl(size: sizes.sideDiskSize, offsetX: sizes.sideDiskOffsetNext)

                            if let upnextLabel {
                                sideLabel(upnextLabel, alignment: .trailing)
                                    .padding(.trailing, sizes.sideLabelInset)
                                    .padding(.top, sizes.sideLabelTopInset)
                            }
                        }
                        .frame(width: sizes.sideSlotWidth, height: sizes.sideSlotHeight)
                    }

                    Spacer()
                }
                .offset(y: sizes.mainVStackOffsetY)

                // The TimelineView wraps ONLY the spinning disc. It previously wrapped this whole
                // ZStack, so the two static side discs, both side labels, the shade and the
                // positioning all re-evaluated at 60-120fps for no reason — nothing outside the
                // hero disc changes between frames.
                TimelineView(.animation) { timeline in
                    heroVinyl(timeline: timeline, size: sizes.heroDiskSize)
                }
                .overlay {
                    vinylShade
                }
                .position(
                    x: geo.size.width / 2,
                    y: heroCenterY(for: geo.size.height)
                )
            }
        }
        .background(Color(hex: "101010"))
        .onAppear {
            syncPlaybackState(at: .now)
        }
        .onChange(of: isPlaying) { _, _ in
            syncPlaybackState(at: .now)
        }
    }

    @ViewBuilder
    func previousVinyl(size: CGFloat, offsetX: CGFloat) -> some View {
        if let previous {
            VinylDisk(size: size) {
                previous()
            }
            .offset(x: offsetX)
        }
    }

    @ViewBuilder
    func nextVinyl(size: CGFloat, offsetX: CGFloat) -> some View {
        if let upnext {
            VinylDisk(size: size) {
                upnext()
            }
            .offset(x: offsetX)
        }
    }

    func heroVinyl(timeline: TimelineViewDefaultContext, size: CGFloat) -> some View {
        VinylDisk(size: size, rotation: rotation(at: timeline.date)) {
            content()
        }
    }

    private var vinylShade: LinearGradient {
        let accent = accentColor
        return LinearGradient(
            colors: [
                .black,
                accent.opacity(0.92),
                accent.opacity(0.68),
                accent.opacity(0.42),
                .clear,
                .clear,
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func sideLabel(_ label: VinylSideLabel, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment) {
            Text(label.title)
                .font(.system(size: 17))
                .lineLimit(1)

            if let subtitle = label.subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 140, alignment: alignment == .leading ? .leading : .trailing)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .fontWeight(.semibold)
    }

    private func heroCenterY(for height: CGFloat) -> CGFloat {
        let compactAnchor: CGFloat = 850
        let tallAnchor: CGFloat = 930

        let ratio: CGFloat
        if height <= compactAnchor {
            ratio = 0.77
        } else if height >= tallAnchor {
            ratio = 0.75
        } else {
            let progress = (height - compactAnchor) / (tallAnchor - compactAnchor)
            ratio = 0.77 - (0.02 * progress)
        }

        return height * ratio
    }

    public func rotation(at date: Date) -> Double {
        spin.rotation(at: date)
    }

    private func syncPlaybackState(at date: Date) {
        spin.syncPlaybackState(at: date, isPlaying: isPlaying)
    }
}

/// A record: artwork under grooves and a gloss overlay, with the centre label on top.
///
/// The disc is deliberately dumb about time. The caller owns the angle, so a static disc costs
/// nothing — no `TimelineView`, no per-frame re-evaluation — and only the spinning one pays.
struct VinylDisk<Content: View>: View {
    let size: CGFloat

    /// Current angle in degrees. Defaults to 0 so a static disc reads as `VinylDisk(size:) { ... }`.
    var rotation: Double = 0

    /// How strongly the groove texture reads. The hero player sits on its own opaque
    /// backdrop and wants it subtle; the macOS band is small and needs the disc legible.
    var grooveOpacity: Double = 0.5

    /// Declared last so the trailing closure binds here rather than to `rotation`.
    let content: () -> Content

    var body: some View {
        ZStack {
            Group {
                Circle()
                    .fill(.clear)
                    .overlay {
                        content()
                    }
                    .clipShape(.circle)
                    .padding(1)

                Image.vinylGrooves
                    .resizable()
                    .scaledToFill()
                    .opacity(grooveOpacity)
                    .padding(5)

                Image.vinylOverlay
                    .resizable()
                    .scaledToFill()
            }
            .rotationEffect(.degrees(rotation))

            // Outside the rotating group on purpose: the centre label is the fixed spindle area,
            // and spinning it made the whole disc read as a flat rotating image.
            Image.vinylCenter
                .resizable()
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    Vinyl(
        isPlaying: false,
        accentColor: .blue,
        content: {
            Color.gray
        },
        previous: {
            Color.gray
        },
        upnext: {
            Color.gray
        },
        previousTitle: "title",
        previousSubtitle: "subtitle",
        upnextTitle: "title",
        upnextSubtitle: "subtitle"
    )
    .preferredColorScheme(.dark)
}

public extension Vinyl where Previous == EmptyView, UpNext == EmptyView {
    init(
        isPlaying: Bool,
        accentColor: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.content = content
        self.previous = nil
        self.upnext = nil
        self.previousLabel = nil
        self.upnextLabel = nil
    }
}

public extension Vinyl where UpNext == EmptyView {
    init(
        isPlaying: Bool,
        accentColor: Color,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder previous: @escaping () -> Previous,
        previousTitle: String? = nil,
        previousSubtitle: String? = nil
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.content = content
        self.previous = previous
        self.upnext = nil
        self.previousLabel = Self.makeSideLabel(title: previousTitle, subtitle: previousSubtitle)
        self.upnextLabel = nil
    }
}

public extension Vinyl where Previous == EmptyView {
    init(
        isPlaying: Bool,
        accentColor: Color,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder upnext: @escaping () -> UpNext,
        upnextTitle: String? = nil,
        upnextSubtitle: String? = nil
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.content = content
        self.previous = nil
        self.upnext = upnext
        self.previousLabel = nil
        self.upnextLabel = Self.makeSideLabel(title: upnextTitle, subtitle: upnextSubtitle)
    }
}

public extension Vinyl {
    init(
        isPlaying: Bool,
        accentColor: Color,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder previous: @escaping () -> Previous,
        @ViewBuilder upnext: @escaping () -> UpNext,
        previousTitle: String? = nil,
        previousSubtitle: String? = nil,
        upnextTitle: String? = nil,
        upnextSubtitle: String? = nil
    ) {
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.content = content
        self.previous = previous
        self.upnext = upnext
        self.previousLabel = Self.makeSideLabel(title: previousTitle, subtitle: previousSubtitle)
        self.upnextLabel = Self.makeSideLabel(title: upnextTitle, subtitle: upnextSubtitle)
    }

    private static func makeSideLabel(title: String?, subtitle: String?) -> VinylSideLabel? {
        guard let title else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let trimmedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubtitle = (trimmedSubtitle?.isEmpty == false) ? trimmedSubtitle : nil
        return VinylSideLabel(title: trimmedTitle, subtitle: normalizedSubtitle)
    }
}
