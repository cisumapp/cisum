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

    public init(sidebar: some View, detail: some View, detailKey: Int) {
        self.sidebar = AnyView(sidebar)
        self.detail = AnyView(detail)
        self.detailKey = detailKey
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
        sidebarItem.canCollapse = false
        // Left without an identifier deliberately: AppKit then has no key under which to
        // autosave this column's frame, so a stale width from an earlier build cannot come
        // back and override the one set below.
        sidebarItem.viewController.view.identifier = nil

        let detailItem = NSSplitViewItem(viewController: detailHost)
        detailItem.minimumThickness = 420

        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        split.splitView.dividerStyle = .thin

        // The divider keeps doing its job — it is the drag handle — but stops drawing a line
        // along it. The sidebar surface already ends on this edge and the reference shows the
        // two meeting without a rule between them; a drawn divider would put a hard vertical
        // seam exactly where the composition is supposed to be continuous.
        //
        // AppKit creates these views lazily, so this has to run after the items are added and
        // again once the split has been sized.
        Self.hideDividers(in: split)
        DispatchQueue.main.async {
            Self.hideDividers(in: split)
        }

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost
        context.coordinator.detailKey = detailKey

        return split
    }

    /// Makes the split view's divider views invisible without disabling them.
    ///
    /// Clearing the layer rather than hiding the view is deliberate: a hidden divider cannot be
    /// hit-tested, so the column would stop being resizable and the resize affordance would
    /// have to be faked somewhere else. This leaves the drag behaviour untouched.
    ///
    /// `NSSplitViewDividerView` is not public, so the views are matched by class name rather
    /// than cast — there is no supported way to reference the type directly.
    private static func hideDividers(in controller: NSSplitViewController) {
        for view in controller.splitView.subviews
            where String(describing: type(of: view)) == "NSSplitViewDividerView"
        {
            view.wantsLayer = true
            view.layer?.backgroundColor = .clear
        }
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
    public static let sidebarMargin: CGFloat = 10

    /// Total thickness of the column: the surface plus the leading margin.
    ///
    /// Adding the margin on both sides is what produced a dead strip between the visible
    /// surface and the divider, so only the leading one is counted here.
    public static var sidebarColumnWidth: CGFloat {
        sidebarWidth + sidebarMargin
    }

    public func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        // The divider position is only valid once the split view has been given a size, which
        // has not happened by the time `makeNSViewController` returns. One deferred pass is
        // enough, and doing it only once leaves the user's own drag widths alone afterwards.
        if !context.coordinator.hasSetInitialWidth {
            context.coordinator.hasSetInitialWidth = true
            DispatchQueue.main.async {
                controller.splitView.setPosition(Self.sidebarColumnWidth, ofDividerAt: 0)
            }
        }

        context.coordinator.detailKey = detailKey
        // Only swap the hosted root when the tab actually changed. Reassigning on every update
        // would rebuild the detail column's scroll position, focus and animations each time
        // the sidebar's own state changes.
        guard context.coordinator.detailKey != detailKey else { return }
        context.coordinator.detailKey = detailKey
        context.coordinator.detailHost?.rootView = AnyView(detail.ignoresSafeArea(.all))
    }

    public final class Coordinator {
        var sidebarHost: NSHostingController<AnyView>?
        var detailHost: NSHostingController<AnyView>?
        var detailKey: Int = 0
        var hasSetInitialWidth = false
    }
}
#endif
