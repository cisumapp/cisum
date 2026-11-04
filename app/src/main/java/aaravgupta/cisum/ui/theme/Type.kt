package aaravgupta.cisum.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * SwiftUI's Dynamic Type sizes (iOS "Large" default), so `.font(.caption)` etc. port by name.
 * ponytail: system sans (Roboto) stands in for SF Pro; bundle Inter if the difference matters.
 */
object IOSFont {
    val largeTitle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold)
    val title = TextStyle(fontSize = 28.sp)
    val title2 = TextStyle(fontSize = 22.sp)
    val title3 = TextStyle(fontSize = 20.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 17.sp)
    val callout = TextStyle(fontSize = 16.sp)
    val subheadline = TextStyle(fontSize = 15.sp)
    val footnote = TextStyle(fontSize = 13.sp)
    val caption = TextStyle(fontSize = 12.sp)
    val caption2 = TextStyle(fontSize = 11.sp)
}

val Typography = Typography(
    bodyLarge = IOSFont.body,
    bodyMedium = IOSFont.subheadline,
    bodySmall = IOSFont.caption,
    titleLarge = IOSFont.title2,
    titleMedium = IOSFont.headline,
    labelSmall = IOSFont.caption2,
)
