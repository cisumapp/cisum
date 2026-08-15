import Foundation

/// Checks a public JSON (`app.json` on GitHub, served via raw.githubusercontent CDN) for a newer
/// TestFlight build and drives an in-app "Update Available" alert. Edit the file per release; the
/// app compares `latest_build` against its own `CFBundleVersion`. `min_build` forces the update.
@Observable
@MainActor
public final class AppUpdateChecker {
    public var updateAvailable = false
    public var forced = false
    public var downloadURL: URL?
    public var message = "A new version of cisum is available."

    /// Public raw JSON the app checks on launch.
    /// NOTE: the repo must be **public** — raw.githubusercontent CDN needs no auth only for public repos.
    /// If cisumapp/cisum is private, host app.json in a public repo/gist and change this URL.
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/cisumapp/cisum/main/app.json")!

    public init() {}

    private struct Manifest: Decodable {
        let latest_build: Int
        let download_url: String?
        let message: String?
        let min_build: Int?
    }

    private var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// Pure gate logic, extracted so it stays testable (see `_selfCheck`).
    static func evaluate(currentBuild: Int, latestBuild: Int, minBuild: Int) -> (show: Bool, forced: Bool) {
        (latestBuild > currentBuild, minBuild > currentBuild)
    }

    // ponytail: best-effort; any network/parse failure is silent — never block launch on it.
    public func check(url: URL = manifestURL) async {
        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData // skip device cache; CDN TTL still applies
            let (data, _) = try await URLSession.shared.data(for: req)
            let m = try JSONDecoder().decode(Manifest.self, from: data)
            let (show, force) = Self.evaluate(
                currentBuild: currentBuild,
                latestBuild: m.latest_build,
                minBuild: m.min_build ?? 0
            )
            guard show else { return }
            forced = force
            if let s = m.download_url, let u = URL(string: s) {
                downloadURL = u
            } else {
                downloadURL = URL(string: "itms-beta://")
            } // fallback: opens TestFlight app
            if let msg = m.message, !msg.isEmpty {
                message = msg
            }
            updateAvailable = true
        } catch {
            // silent
        }
    }
}

#if DEBUG
extension AppUpdateChecker {
    /// ponytail: one runnable check for the gate logic. Fails loudly if the compare breaks.
    static func _selfCheck() {
        assert(evaluate(currentBuild: 4, latestBuild: 4, minBuild: 0) == (false, false))
        assert(evaluate(currentBuild: 4, latestBuild: 5, minBuild: 0) == (true, false))
        assert(evaluate(currentBuild: 4, latestBuild: 5, minBuild: 5) == (true, true))
        assert(evaluate(currentBuild: 4, latestBuild: 5, minBuild: 4) == (true, false))
    }
}
#endif
