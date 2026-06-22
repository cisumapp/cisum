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

    @State private var phaseStartAngle: Double = 0
    @State private var phaseStartDate: Date?
    @State private var phaseStartSpeed: Double = 0
    @State private var phaseTargetSpeed: Double = 0
    @State private var phaseTau: Double = 0.67

    private let targetMaxSpeed: Double = 35
    private let tauStart: Double = 0.6
    private let tauStop: Double = 0.67

    public var body: some View {
        GeometryReader { geo in
            let sizes = ResponsiveLayout.VinylSizes(screenWidth: geo.size.width)
            
            TimelineView(.animation) { timeline in
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

                    heroVinyl(timeline: timeline, size: sizes.heroDiskSize)
                        .overlay {
                            vinylShade
                        }
                        .position(
                            x: geo.size.width / 2,
                            y: heroCenterY(for: geo.size.height)
                        )
                }
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
        VinylDisk(size: size) {
            content()
        }
        .rotationEffect(.degrees(rotation(at: timeline.date)))
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

            if let subtitle = label.subtitle,
               !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        guard let phaseStartDate else {
            return phaseStartAngle
        }

        let elapsed = max(date.timeIntervalSince(phaseStartDate), 0)
        let deltaSpeed = phaseStartSpeed - phaseTargetSpeed

        // Fast path once acceleration settles to steady-state motion.
        if abs(deltaSpeed) < 0.0001 {
            return phaseStartAngle + (phaseTargetSpeed * elapsed)
        }

        return phaseStartAngle + (phaseTargetSpeed * elapsed)
            + (deltaSpeed * phaseTau * (1 - exp(-elapsed / phaseTau)))
    }

    private func speed(at date: Date) -> Double {
        guard let phaseStartDate else { return 0 }
        let elapsed = max(date.timeIntervalSince(phaseStartDate), 0)
        let delta = phaseStartSpeed - phaseTargetSpeed
        if abs(delta) < 0.0001 {
            return phaseTargetSpeed
        }
        return phaseTargetSpeed + delta * exp(-elapsed / phaseTau)
    }

    private func syncPlaybackState(at date: Date) {
        let currentAngle = rotation(at: date)
        let currentSpeed = speed(at: date)
        let nextTargetSpeed = isPlaying ? targetMaxSpeed : 0
        let nextTau = isPlaying ? tauStart : tauStop

        phaseStartAngle = currentAngle
        phaseStartDate = date
        phaseStartSpeed = currentSpeed
        phaseTargetSpeed = nextTargetSpeed
        phaseTau = nextTau
    }
}

struct VinylDisk<Content: View>: View {
    let size: CGFloat
    let content: () -> Content

    var body: some View {
        ZStack {
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
                .opacity(0.5)
                .padding(5)

            Image.vinylOverlay
                .resizable()
                .scaledToFill()

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
