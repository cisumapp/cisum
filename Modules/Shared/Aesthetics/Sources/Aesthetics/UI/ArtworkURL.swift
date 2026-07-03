import Foundation

/// Upgrades an artwork URL to the highest resolution each CDN offers, so the app can downscale a
/// crisp source with Kingfisher instead of upscaling a small one.
///
/// - Apple Music / iTunes (`*.mzstatic.com/.../{w}x{h}bb.jpg`): the size segment is freely
///   resizable → request 1000×1000.
/// - Spotify (`i.scdn.co/image/ab67616d…`): the 8 hex after the image-type code encode the size;
///   `0000b273` = 640² is the largest Spotify serves for cover art → normalize to it.
/// - Google / YouTube-Music CDNs (`=w{n}-h{n}`, `=s{n}`) support arbitrary sizes → request 1000².
/// - Plain YouTube video thumbnails (`i.ytimg.com`) cap at `sddefault` (640×480); `maxresdefault`
///   often 404s, so request the largest reliably-present size. (Prefer not to use these at all.)
public enum ArtworkURL {
    public static func best(from url: URL?) -> URL? {
        guard let url else { return nil }
        var str = url.absoluteString

        // Apple Music / iTunes — force 1000² (supports far larger, 1000 is a crisp, light target).
        if str.contains("mzstatic.com"),
           let r = str.range(of: #"\d+x\d+"#, options: .regularExpression) {
            str.replaceSubrange(r, with: "1000x1000")
            return URL(string: str) ?? url
        }

        // Spotify cover art — normalize the size code to the 640² maximum.
        if str.contains("i.scdn.co/image/ab67616d"),
           let r = str.range(of: #"ab67616d[0-9a-f]{8}"#, options: .regularExpression) {
            str.replaceSubrange(r, with: "ab67616d0000b273")
            return URL(string: str) ?? url
        }

        // Google / YouTube-Music CDNs — arbitrary sizes.
        if let r = str.range(of: #"w\d+-h\d+"#, options: .regularExpression) {
            str.replaceSubrange(r, with: "w1000-h1000")
            return URL(string: str) ?? url
        }
        if let r = str.range(of: #"(?<==)s\d+"#, options: .regularExpression) {
            str.replaceSubrange(r, with: "s1000")
            return URL(string: str) ?? url
        }

        // Plain YouTube video thumbnails — capped; sddefault is the largest reliably present.
        if str.contains("ytimg.com"),
           let r = str.range(of: #"/(default|mqdefault|hqdefault|sddefault|maxresdefault)\.jpg"#, options: .regularExpression) {
            str.replaceSubrange(r, with: "/sddefault.jpg")
            return URL(string: str) ?? url
        }
        return url
    }
}
