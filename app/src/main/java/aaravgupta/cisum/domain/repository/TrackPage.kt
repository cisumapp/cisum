package aaravgupta.cisum.domain.repository

import aaravgupta.cisum.data.model.Track

data class TrackPage(
    val items: List<Track>,
    val hasMore: Boolean
)
