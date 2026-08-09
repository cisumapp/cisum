//
//  TabBarGeometryProbe.swift
//  cisum
//

#if os(iOS)
import SwiftUI

public extension View {
    /// Records the real frame of the native tab-view bottom accessory.
    ///
    /// Attach to the accessory's content, inside `.tabViewBottomAccessory { }`.
    /// In release builds this is the identity modifier — no measurement, no cost.
    @ViewBuilder
    func measureTabAccessoryGeometry() -> some View {
        #if DEBUG
        if #available(iOS 26.0, *) {
            modifier(TabAccessoryPlacementProbe())
                .modifier(TabAccessoryGeometryProbe())
        } else {
            modifier(TabAccessoryGeometryProbe())
        }
        #else
        self
        #endif
    }

    /// Floating readout of the latest accessory measurement.
    /// In release builds this is the identity modifier.
    @ViewBuilder
    func tabBarGeometryHUD() -> some View {
        #if DEBUG
        overlay(alignment: .top) {
            TabBarGeometryHUD()
        }
        #else
        self
        #endif
    }
}

#if DEBUG

// MARK: - Probes

/// Records the accessory's frame. Works on every supported OS —
/// `onGeometryChange` is iOS 16+.
private struct TabAccessoryGeometryProbe: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            record(frame: frame)
        }
    }

    private func record(frame: CGRect) {
        let screen = UIScreen.main.bounds
        let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)
            .flatMap { $0.windows.first(where: \.isKeyWindow) }

        TabBarGeometryLog.shared.record(
            TabAccessoryMetrics(
                accessoryFrame: frame,
                placementDescription: TabBarGeometryLog.shared.latestPlacement,
                screenBounds: screen,
                safeAreaBottom: window?.safeAreaInsets.bottom ?? 0,
                safeAreaTop: window?.safeAreaInsets.top ?? 0,
                isLandscape: verticalSizeClass == .compact
            )
        )
    }
}

/// Records `tabViewBottomAccessoryPlacement`. Separate from the frame probe because
/// the environment value is iOS 26-only and an `@Environment` property cannot be
/// declared conditionally — so the whole modifier carries the availability instead.
@available(iOS 26.0, *)
private struct TabAccessoryPlacementProbe: ViewModifier {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    func body(content: Content) -> some View {
        content.onChange(of: describe(placement), initial: true) { _, new in
            TabBarGeometryLog.shared.recordPlacement(new)
        }
    }

    private func describe(_ placement: TabViewBottomAccessoryPlacement?) -> String {
        switch placement {
        case .inline: "inline"
        case .expanded: "expanded"
        case .none: "nil"
        @unknown default: "unknown"
        }
    }
}

// MARK: - HUD

private struct TabBarGeometryHUD: View {
    var body: some View {
        // Polls instead of observing — see TabBarGeometryLog's note.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            readout
        }
    }

    @ViewBuilder
    private var readout: some View {
        let log = TabBarGeometryLog.shared

        VStack(alignment: .leading, spacing: 2) {
            if let latest = log.latest {
                Text("accessory  h \(latest.measuredHeight, specifier: "%.1f")   w \(latest.measuredWidth, specifier: "%.1f")")
                Text("x \(latest.measuredSideInset, specifier: "%.1f")   bottomOffset \(latest.measuredBottomOffset, specifier: "%.1f")")
                Text("placement \(latest.placementDescription)")
                Text("safe t\(latest.safeAreaTop, specifier: "%.0f") b\(latest.safeAreaBottom, specifier: "%.0f")   \(latest.isLandscape ? "landscape" : "portrait")")

                Text("vs const:  h48  w\(latest.screenBounds.width - 42, specifier: "%.0f")  x21  bottom91")
                    .foregroundStyle(.yellow)

                if !latest.looksLikeWindowCoordinates {
                    Text("⚠︎ .global is NOT window space — values unusable")
                        .foregroundStyle(.red)
                }

                Text("distinct samples: \(log.distinctSamples.count)")
                    .foregroundStyle(.secondary)
            } else {
                Text("no accessory measurement yet")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 60)
        .allowsHitTesting(false)
    }
}
#endif
#endif
