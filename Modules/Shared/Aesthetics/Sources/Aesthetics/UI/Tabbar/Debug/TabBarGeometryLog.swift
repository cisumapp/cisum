//
//  TabBarGeometryLog.swift
//  cisum
//

#if DEBUG
#if os(iOS)
import Foundation

/// Collects accessory geometry samples.
///
/// Deliberately **not** `@Observable`: `record` is called from inside
/// `onGeometryChange`, which fires during layout. Mutating observable state there
/// produces "AttributeGraph: setting value during update" — the same failure the
/// tab bar already works around at iOSTabView.swift (the deferred
/// `TabBarStateStore` write inside `.task(id:)`). The HUD polls instead.
@MainActor
public final class TabBarGeometryLog {
    public static let shared = TabBarGeometryLog()

    private init() {}

    public private(set) var latest: TabAccessoryMetrics?

    /// Latest `tabViewBottomAccessoryPlacement`, recorded separately because it is
    /// iOS 26-only and arrives from a different modifier than the frame.
    public private(set) var latestPlacement: String = "unread"

    /// Every geometrically distinct sample seen this session, in arrival order.
    /// Rotating the device or changing placement appends; a redundant relayout does not.
    public private(set) var distinctSamples: [TabAccessoryMetrics] = []

    /// How long a frame must hold still before it counts as a real state.
    ///
    /// Rotation and the tab-bar hide/show animation both walk the accessory through
    /// intermediate frames. Without this, each one is committed as a distinct sample
    /// and swamps the run — the first iPhone 14 run produced 13 samples for roughly
    /// six actual states.
    private static let settleDuration = Duration.milliseconds(300)

    private var pendingSample: TabAccessoryMetrics?
    private var settleToken = 0

    public func record(_ metrics: TabAccessoryMetrics) {
        // The HUD reads `latest`, so it stays live even while a frame is still settling.
        latest = metrics
        pendingSample = metrics
        settleToken &+= 1
        let token = settleToken

        Task { @MainActor in
            try? await Task.sleep(for: Self.settleDuration)
            guard token == settleToken, let settled = pendingSample else { return }
            commit(settled)
        }
    }

    private func commit(_ metrics: TabAccessoryMetrics) {
        guard !distinctSamples.contains(metrics) else { return }
        distinctSamples.append(metrics)
        // Printed as it happens so a run is readable in the Xcode console without
        // pausing in the debugger. `print` rather than PerfLog: this is a DEBUG-only
        // tool and the output must never be filtered away.
        print("[TabGeom] \(distinctSamples.count). \(metrics.summaryLine)")
    }

    /// Called by the iOS 26-only placement probe. Stored for the next frame sample
    /// to pick up — placement changes always trigger a relayout, so the pairing holds.
    public func recordPlacement(_ description: String) {
        latestPlacement = description
    }

    public func reset() {
        latest = nil
        latestPlacement = "unread"
        distinctSamples.removeAll()
        // Invalidate any in-flight settle so it cannot commit into the cleared run.
        pendingSample = nil
        settleToken &+= 1
    }

    /// Paste-ready dump for comparing against `ResponsiveLayout`'s constants.
    public func exportText() -> String {
        guard !distinctSamples.isEmpty else {
            return "no samples"
        }

        return distinctSamples.map(\.summaryLine).joined(separator: "\n")
    }
}
#endif
#endif
