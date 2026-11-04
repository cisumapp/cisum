package aaravgupta.cisum.data.model

data class Track(
    val id: String,
    val title: String,
    val artist: String,
    val artworkUrl: String?,
    val durationMs: Long,
    val streamUrl: String,
    val album: String? = null,
    val isExplicit: Boolean = false,
    /** Set by playback resolution: "YouTube Music", "audio/mp4", "mp4a.40.2". */
    val sourceName: String? = null,
    val mimeType: String? = null,
    val codec: String? = null,
)
