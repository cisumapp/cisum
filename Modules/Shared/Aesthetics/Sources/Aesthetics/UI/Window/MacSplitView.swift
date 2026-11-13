//
//  MacSplitView.swift
//  Aesthetics
//
//  A two-column split built on `NSSplitViewController`, hosted in SwiftUI.
//
//  Why not `NavigationSplitView`: it is a wrapper over the same AppKit controller, but it
//  reserves a strip across the top of the window for its toolbar. Neither
//  `.fullSizeContentView` nor `.toolbar(.hidden)` removes it, because the space belongs to
//  the split view controller inside SwiftUI's own layout rather than to the window — so the
//  sidebar could never reach the window's top edge.
//
//  Hosting the controller directly fixes that: it fills the content view, which
//  `.fullSizeContentView` already spans across the title bar. In exchange the traffic lights
//  have to be drawn by hand, since AppKit will only place its own against the title bar.
//  That is what `WindowControls` is for.
//

#if os(macOS)
import AppKit
import SwiftUI

public struct MacSplitView: NSViewControllerRepresentable {
    /// The navigation column. Created once — its selection is a binding, so it updates
    /// itself without the hosted view being replaced.
    let sidebar: AnyView

    /// The content column.
    let detail: AnyView

    /// Identity of the detail column's content. The hosted root view is only replaced when
    /// this changes, so ordinary state updates in the sidebar do not tear down and rebuild
    /// the detail's scroll position, focus and animations on every pass.
    let detailKey: Int

    /// Folds the sidebar column away, animated.
    let isSidebarCollapsed: Bool

    /// Told when AppKit folds or unfolds the sidebar itself — dragging the divider past the
    /// column's minimum — so the app's flag follows. Without it the flag stayed `false`, the
    /// controls for getting the sidebar back never appeared, and the next update unfolded it.
    let onSidebarCollapsedChange: (Bool) -> Void

    public init(
        sidebar: some View,
        detail: some View,
        detailKey: Int,
        isSidebarCollapsed: Bool = false,
        onSidebarCollapsedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.sidebar = AnyView(sidebar)
        self.detail = AnyView(detail)
        self.detailKey = detailKey
        self.isSidebarCollapsed = isSidebarCollapsed
        self.onSidebarCollapsedChange = onSidebarCollapsedChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSViewController(context: Context) -> NSSplitViewController {
        // Each column is its own `NSHostingController`, which means its own SwiftUI layout
        // pass — `ignoresSafeArea` applied on the `MacSplitView` itself does not reach inside
        // them. AppKit lays these hosted views out against the window's content layout rect,
        // which excludes the title bar, so each column has to opt out for itself. Without
        // this the columns start ~28pt down and a band of bare window background shows above
        // them, which reads as a strip across the top of the window.
        let sidebarHost = NSHostingController(rootView: AnyView(sidebar.ignoresSafeArea(.all)))
        let detailHost = NSHostingController(rootView: AnyView(detail.ignoresSafeArea(.all)))

        let split = NSSplitViewController()
        // NSSplitView paints the divider itself (`drawDivider(in:)`), not through the divider
        // view, so clearing that view's layer left a dark line beside the sidebar.
        let splitView = SeamlessSplitView()
        splitView.isVertical = true
        split.splitView = splitView

        // A plain `viewController:` item, not `sidebarWithViewController:`. The sidebar
        // initialiser makes AppKit inset the column's content by the title bar's height so
        // that native rows clear the title bar — which is precisely the band we are trying to
        // remove, and it is not something `ignoresSafeArea` can undo. The column still looks
        // and behaves like a sidebar because the SwiftUI `List(.sidebar)` inside draws the
        // material, rows and selection; the split item only supplies the divider and the
        // resize behaviour.
        let sidebarItem = NSSplitViewItem(viewController: sidebarHost)
        // Matches the reference's proportions and stops the column being dragged to a
        // width that leaves no room for the content.
        //
        // The column's trailing edge *is* the sidebar surface's trailing edge. There is no
        // margin on that side, so the surface ends exactly where the divider is and the user
        // perceives one edge rather than a surface with a strip of empty, draggable gutter
        // beside it. The margin only exists on the three sides that face the window frame.
        sidebarItem.minimumThickness = Self.sidebarColumnWidth
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        // Left without an identifier deliberately: AppKit then has no key under which to
        // autosave this column's frame, so a stale width from an earlier build cannot come
        // back and override the one set below.
        sidebarItem.viewController.view.identifier = nil

        let detailItem = NSSplitViewItem(viewController: detailHost)
        detailItem.minimumThickness = 420

        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        split.splitView.dividerStyle = .thin

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.sidebarItem = sidebarItem
        context.coordinator.onSidebarCollapsedChange = onSidebarCollapsedChange
        // AppKit folds the column on a drag without a KVO change on `isCollapsed`, so the resize
        // notification is what reliably sees it.
        context.coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: split.splitView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated { coordinator?.reportCollapse() }
        }
        context.coordinator.detailHost = detailHost
        context.coordinator.detailKey = detailKey

        return split
    }

    /// Width the sidebar surface is drawn at, before the margin around it.
    ///
    /// Apple Music's sidebar is a fixed, narrow column, so it opens at the narrowest it can be
    /// and grows only if the user drags the divider wider.
    public static let sidebarWidth: CGFloat = 190

    /// Margin the floating sidebar surface insets itself by on the sides facing the window.
    ///
    /// Leading, top and bottom only. The trailing side deliberately has none — see
    /// `sidebarColumnWidth`.
    public static let sidebarMargin: CGFloat = 8

    /// The sidebar's fold, shared by everything that moves with it so they land together.
    public static let sidebarAnimationDuration: Double = 0.25
    public static var sidebarAnimation: Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: sidebarAnimationDuration)
    }

    /// Total thickness of the column: the surface plus the leading margin.
    ///
    /// Adding the margin on both sides is what produced a dead strip between the visible
    /// surface and the divider, so only the leading one is counted here.
    public static var sidebarColumnWidth: CGFloat {
        sidebarWidth + sidebarMargin
    }

    public func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.onSidebarCollapsedChange = onSidebarCollapsedChange
        // The divider position is only valid once the split view has been given a size, which
        // has not happened by the time `makeNSViewController` returns. One deferred pass is
        // enough, and doing it only once leaves the user's own drag widths alone afterwards.
        if !context.coordinator.hasSetInitialWidth {
            context.coordinator.hasSetInitialWidth = true
            let collapsed = isSidebarCollapsed
            let item = context.coordinator.sidebarItem
            DispatchQueue.main.async {
                // A collapsible item can be folded by AppKit during the window's first sizing
                // pass; the app's own flag decides, not that.
                item?.isCollapsed = collapsed
                controller.splitView.setPosition(Self.sidebarColumnWidth, ofDividerAt: 0)
            }
        }

        if let item = context.coordinator.sidebarItem, item.isCollapsed != isSidebarCollapsed {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                item.isCollapsed = isSidebarCollapsed
            } else {
                NSAnimationContext.runAnimationGroup { animation in
                    animation.duration = Self.sidebarAnimationDuration
                    // The drawer curve: starts fast, settles softly. The default was AppKit's
                    // gentle ease-in-out, which felt late to start.
                    animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                    animation.allowsImplicitAnimation = true
                    item.animator().isCollapsed = isSidebarCollapsed
                }
            }
        }

        // Only swap the hosted root when the tab actually changed. Reassigning on every update
        // would rebuild the detail column's scroll position, focus and animations each time
        // the sidebar's own state changes. (The key used to be stored just above this guard, so
        // it always returned and the tabs never changed.)
        guard context.coordinator.detailKey != detailKey else { return }
        context.coordinator.detailKey = detailKey
        context.coordinator.detailHost?.rootView = AnyView(detail.ignoresSafeArea(.all))
    }

    /// Keeps the 1pt divider as the resize handle but draws nothing in it.
    final class SeamlessSplitView: NSSplitView {
        override func drawDivider(in _: NSRect) {}
    }

    @MainActor
    public final class Coordinator {
        var sidebarHost: NSHostingController<AnyView>?
        var sidebarItem: NSSplitViewItem?
        var detailHost: NSHostingController<AnyView>?
        var detailKey: Int = 0
        var hasSetInitialWidth = false
        var onSidebarCollapsedChange: ((Bool) -> Void)?
        var resizeObserver: NSObjectProtocol?
        private var lastReportedCollapse: Bool?

        func reportCollapse() {
            guard let collapsed = sidebarItem?.isCollapsed, collapsed != lastReportedCollapse else { return }
            lastReportedCollapse = collapsed
            // Deferred: this fires inside AppKit's layout pass, and the flag change re-enters
            // SwiftUI's update.
            Task { @MainActor in self.onSidebarCollapsedChange?(collapsed) }
        }
    }
}
#endif
