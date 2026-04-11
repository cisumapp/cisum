//
//  NowPlayingView.swift
//  cisum
//
//  Created by Aarav Gupta on 05/12/25.
//

#if os(iOS)
import SwiftUI

struct NowPlayingView: View {
    @Environment(PlayerViewModel.self) var playerViewModel

    var isPlayerExpanded: Bool
    var size: CGSize
    var namespace: Namespace.ID
    
#if DEBUG
    @ObserveInjection var forceRedraw
#endif

    var body: some View {
        VStack(spacing: 12) {
            header
            
            artwork
            
            songInfo
            
            playerControls
        }
        .padding(.top, Constants.safeAreaInsets.top)
        .padding(.bottom, Constants.safeAreaInsets.bottom)
        .enableInjection()
    }
}
#endif

private extension NowPlayingView {
    var header: some View {
        Capsule()
            .fill(.white.secondary)
            .blendMode(.overlay)
            .opacity(isPlayerExpanded ? 1 : 0)
            .frame(width: 40, height: 5)
            .offset(y: 10)
            .onTapGesture {
//                withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
//                    /// Closing View
//                    isPlayerExpanded = false
//                    /// Resetting Window to identity with Animation
//                    resetWindowWithAnimation()
//
//                    offsetY = 0
//                }
            }
    }
    
    @ViewBuilder
    var artwork: some View {
        GeometryReader { geometry in
            Color.clear
            .frame(width: geometry.size.width, height: geometry.size.width)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 15)
    }
    
    @ViewBuilder
    var songInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(playerViewModel.currentTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    if playerViewModel.isExplicit {
                        Text("E")
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(4)
                            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                Text(playerViewModel.currentArtist)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 8) {
                    infoBadge(title: playerViewModel.currentStreamingServiceName, systemImage: "dot.radiowaves.left.and.right")
                    infoBadge(
                        title: "\(playerViewModel.currentAudioQualityLabel) • \(playerViewModel.currentAudioCodecLabel)",
                        systemImage: "waveform"
                    )
                }

                if let hiResMessage = playerViewModel.hiResAvailabilityMessage {
                    Text(hiResMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.32), in: Capsule())
                        .accessibilityLabel("Hi-Res available")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Button {
                    
                } label: {
                    Image(systemName: "star")
                }
                
                Menu {
                    Button {
                        Task {
                            await playerViewModel.checkForHiResVersion()
                        }
                    } label: {
                        Label(
                            playerViewModel.isCheckingHiResAvailability ? "Checking Hi-Res..." : "Check Hi-Res Availability",
                            systemImage: "waveform.badge.magnifyingglass"
                        )
                    }
                    .disabled(playerViewModel.isCheckingHiResAvailability || playerViewModel.currentVideoId == nil)

                    if playerViewModel.canSwitchToHiResVersion {
                        Button {
                            playerViewModel.switchToHiResVersionIfAvailable()
                        } label: {
                            Label("Switch to Hi-Res", systemImage: "arrow.up.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .foregroundStyle(.white)
            .font(.title2)
            .frame(alignment: .trailing)
        }
        .frame(height: 80)
        .padding(.top, 80)
        .padding(.horizontal, 15)
    }
    
    @ViewBuilder
    var playerControls: some View {
        GeometryReader {
            let size = $0.size
            let safeArea = $0.safeAreaInsets
            
            VStack {
                MusicProgressScrubber(
                    mediaID: playerViewModel.currentVideoId,
                    currentTime: playerViewModel.currentTime,
                    duration: playerViewModel.duration,
                    onSeek: { newTime in
                        playerViewModel.seek(to: newTime)
                    }
                )
                .frame(height: 30)
                
                Spacer(minLength: 0)
                
                // Buttons
                HStack(spacing: size.width * 0.18) {
                    PreviousButton()
                    
                    TogglePlayPauseButton()
                        .disabled(playerViewModel.currentVideoId == nil)
                    
                    ForwardButton()
                }
                .foregroundColor(.white)
                
                Spacer(minLength: 0)
                
                VolumeSlider()
                    .frame(height: 30)
                
                Spacer(minLength: 0)
                
                // Bottom Buttons
                footer(size: size, safeArea: safeArea)
            }
            .padding(.horizontal, 15)
        }
    }
    
    @ViewBuilder
    func footer(size: CGSize, safeArea: EdgeInsets) -> some View {
        HStack(alignment: .top, spacing: size.width * 0.18) {
            Button {
                
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.title2)
            }
            
            AirPlayButton(activeTintColor: playerViewModel.currentAccentColor.uiColor)
                .frame(width: 48, height: 48)
                .padding(.top, -13)
            
            Button {
                withAnimation {
                    
                }
                // Optional: Show a toast or feedback that queue was cleared
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title2)
            }
        }
        .foregroundColor(.white)
        .blendMode(.overlay)
    }
    
    func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private func infoBadge(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2), in: Capsule())
            .foregroundStyle(.white)
    }
}
