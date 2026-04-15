import SwiftUI
import YouTubeSDK

struct HomeView: View {
    @State private var viewModel: HomeViewModel

    init(youtube: YouTube) {
        _viewModel = State(initialValue: HomeViewModel(youtube: youtube))
    }

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header

                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading Home Feed...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                }

                if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "Unable to Load Home",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )

                    Button("Retry") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                ForEach(viewModel.items) { item in
                    HomeFeedRow(item: item)
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentItemID: item.id)
                        }
                }

                if viewModel.isLoadingMore {
                    ProgressView("Loading More...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                if let footerMessage = viewModel.footerMessage, !viewModel.items.isEmpty {
                    Text(footerMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }
            }
            .safeAreaPadding(.horizontal, 18)
            .safeAreaPadding(.top, 18)
            .safeAreaPadding(.bottom, 120)
        }
        .background {
            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.black.opacity(0.12), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .enableInjection()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back,")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Aarav Gupta")
                .font(.largeTitle.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeFeedRow: View {
    let item: HomeFeedDisplayItem

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.symbolName)

                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cisumGlassCard(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .enableInjection()
    }
}

#Preview {
    HomeView(youtube: YouTube())
        .injectPreviewDependencies()
}
