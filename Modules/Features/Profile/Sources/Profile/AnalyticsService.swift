import Foundation
import Observation
import PostHog

@Observable
@MainActor
public final class AnalyticsService {
    private let projectToken: String = "phc_BiEiUXcrGHDqDSMuaLQrq2MhcJFyTp97WEcF5baG2A9V"
    private let host: String = "https://eu.i.posthog.com"

    public private(set) var isInitialized: Bool = false

    public init() {
        setupPostHog()
    }

    private func setupPostHog() {
        let currentProjectToken = self.projectToken
        let currentHost = self.host
        Task.detached {
            let config = PostHogConfig(projectToken: currentProjectToken, host: currentHost)
            config.preloadFeatureFlags = false
            PostHogSDK.shared.setup(config)
            await MainActor.run {
                self.isInitialized = true
            }
        }
    }

    /// Identify the current user
    /// This must be called after successful authentication to link events to the user
    public func identify(userId: String, properties: [String: Any]? = nil) {
        let props = properties ?? [:]
        PostHogSDK.shared.identify(userId, userProperties: props)
    }

    /// Capture a custom event
    public func captureEvent(_ eventName: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(eventName, properties: properties ?? [:])
    }

    /// Clear current user identity (for sign-out)
    public func reset() {
        PostHogSDK.shared.reset()
    }
}
