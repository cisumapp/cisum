package aaravgupta.cisum.data.remote.itunes

import aaravgupta.cisum.data.model.Track
// import aaravgupta.ituneskit.iTunesClient as iTunesClientSDK
// import aaravgupta.ituneskit.iTunesKit
// import aaravgupta.ituneskit.iTunesSearchResult

class iTunesClient(
    private val iTunesClient: Any? = null // iTunesClientSDK = iTunesKit()
) {
    suspend fun getDiscoverSongs(queries: List<String> = DEFAULT_DISCOVER_QUERIES): List<Track> {
        return emptyList() // TODO stub
    }

    /*
    private fun toTrack(result: iTunesSearchResult): Track? {
        val streamUrl = result.previewUrl
            ?.trim()
            ?.takeIf { preview ->
                preview.startsWith("http://") || preview.startsWith("https://")
            }
            ?: return null

        val identifier = result.trackId?.toString()
            ?: result.trackViewUrl
                ?.takeIf { url -> url.isNotBlank() }
                ?.let { url -> "url-${url.hashCode()}" }
            ?: return null

        val title = result.trackName
            ?: result.collectionName
            ?: return null

        return Track(
            id = "itunes-$identifier",
            title = title,
            artist = result.artistName?.ifBlank { "Unknown Artist" } ?: "Unknown Artist",
            artworkUrl = result.artworkUrl100 ?: result.artworkUrl60 ?: result.artworkUrl30,
            durationMs = DEFAULT_PREVIEW_DURATION_MS,
            streamUrl = streamUrl
        )
    }
    */

    private companion object {
        val DEFAULT_DISCOVER_QUERIES = listOf(
            "today's top hits",
            "new music friday",
            "viral hits"
        )
        const val DEFAULT_PREVIEW_DURATION_MS = 30_000L
        const val MAX_DISCOVER_TRACKS = 36
    }
}
