import SwiftUI
import YouTubeSDK

struct ProfileView: View {
    @Environment(\.router) private var router
    @Environment(\.youtube) private var youtube

    @State private var hasActiveSession: Bool = false
    @State private var sessionSummary: String = "No active cookie session"

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                sessionCard

                HStack(spacing: 10) {
                    Button("Refresh Session Status") {
                        refreshSessionState()
                    }
                    .buttonStyle(.bordered)

                    Button("Open Settings") {
                        router.navigate(to: .settings)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if hasActiveSession {
                    Button(role: .destructive) {
                        youtube.cookies = nil
                        refreshSessionState()
                    } label: {
                        Label("Clear In-Memory Session", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .safeAreaPadding(.horizontal, 18)
            .safeAreaPadding(.top, 18)
            .safeAreaPadding(.bottom, 40)
        }
        .onAppear {
            refreshSessionState()
        }
        .enableInjection()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profile")
                .font(.largeTitle.weight(.semibold))
            Text("Session and account diagnostics for macOS testing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: hasActiveSession ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(hasActiveSession ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasActiveSession ? "Session Detected" : "No Session")
                    .font(.headline)
                Text(sessionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .cisumGlassCard(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func refreshSessionState() {
        let cleaned = youtube.cookies?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasActiveSession = !cleaned.isEmpty

        if hasActiveSession {
            let prefix = cleaned.prefix(36)
            sessionSummary = "Cookie payload detected: \(prefix)..."
        } else {
            sessionSummary = "No active cookie session"
        }
    }
}

#Preview {
    ProfileView()
        .injectPreviewDependencies()
}
