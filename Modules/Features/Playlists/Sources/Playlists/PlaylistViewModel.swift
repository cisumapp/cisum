//
//  PlaylistViewModel.swift
//  Albums
//
//  Created by Aarav Gupta on 19/05/26.
//

import Aesthetics
import Kingfisher
import SwiftUI

// MARK: - State Owner

@MainActor @Observable
public final class PlaylistViewModel {
    var palette: ImageColorPalette?

    private var hasFetched = false

    var backgroundColor: Color {
        palette?.background ?? .black
    }

    var titleColor: Color {
        palette?.title ?? .white
    }

    func fetchPaletteIfNeeded(from thumbnailURL: URL) async {
        guard !hasFetched else { return }
        hasFetched = true

        // `data()` hands back the original bytes on a network fetch and re-serialises
        // from the cache on a hit, so it is preferred over re-encoding the image.
        // `pngData()` is the fallback for the rare case where neither yields anything.
        let data: Data?
        do {
            let result = try await KingfisherManager.shared.retrieveImage(with: thumbnailURL)
            data = result.data() ?? result.image.pngData()
        } catch {
            data = nil
        }

        guard let data,
              let extracted = await ImageColorExtractor.shared.extractPalette(
                  from: data,
                  cacheKey: thumbnailURL.absoluteString
              )
        else { return }

        palette = extracted
    }
}
