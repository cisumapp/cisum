//
//  Image+PNGData.swift
//  Aesthetics
//
//  `UIImage.pngData()` has no AppKit counterpart, so the palette pipeline — which
//  feeds Kingfisher's `KFCrossPlatformImage` straight into `ImageColorExtractor` —
//  has nothing to call on macOS. This restores the method, byte-identically shaped,
//  so `result.image.pngData()` reads the same on both platforms.
//

import ImageIO
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

public extension NSImage {
    /// PNG-encoded bytes for this image, or `nil` if it has no bitmap representation.
    ///
    /// Encodes the underlying `CGImage` straight through ImageIO rather than going via
    /// `tiffRepresentation`. That matters for two reasons: an `NSImage` may be backed by
    /// a PDF or a multi-representation TIFF (where a TIFF round-trip re-flattens, at
    /// extra cost, only for us to throw the result away), and `cgImage(forProposedRect:)`
    /// is the one accessor that normalises any of those to a single bitmap.
    ///
    /// Mirrors `UIImage.pngData()` exactly, including the method shape, so call sites
    /// need no platform branch.
    func pngData() -> Data? {
        var rect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }
}
#endif
