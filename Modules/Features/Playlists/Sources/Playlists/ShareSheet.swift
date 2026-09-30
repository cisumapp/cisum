import Foundation

/// A URL wrapped for `.sheet(item:)` presentation.
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
import SwiftUI
import UIKit

/// Presents the system share sheet for a URL that had to be produced asynchronously (e.g. after a
/// shortener round-trip), where SwiftUI's declarative `ShareLink` can't be used directly.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
#endif
