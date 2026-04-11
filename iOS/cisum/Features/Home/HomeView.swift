//
//  HomeView.swift
//  cisum
//
//  Created by Aarav Gupta on 15/03/26.
//

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
        ZStack {
            Color.black
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ProgressView("Loading Home Feed...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                            .tint(.white)
                    }

                    if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                        ContentUnavailableView(
                            "Unable to Load Home",
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                        .foregroundStyle(.white)

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
                            .tint(.white)
                    }

                    if let footerMessage = viewModel.footerMessage, !viewModel.items.isEmpty {
                        Text(footerMessage)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 120)
            }
            .ignoresSafeArea()
            .contentMargins(.top, 300)
        }
        .ignoresSafeArea()
        .overlay {
            ZStack {
                VStack(alignment: .leading) {
                    Text("Welcome back,")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Aarav Gupta")
                        .font(.title)
                        .fontWeight(.semibold)
                }
                .padding(.top, 22)
                .padding(.leading)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                ProfileButton()
            }
            .padding(.top, 200)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .enableInjection()
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
                    .foregroundStyle(.white)

                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .enableInjection()
    }
}
