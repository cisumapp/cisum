package aaravgupta.cisum.data.remote.youtube

data class YouTubeContinuation<T>(
    val items: List<T>,
    val continuationToken: String?
)