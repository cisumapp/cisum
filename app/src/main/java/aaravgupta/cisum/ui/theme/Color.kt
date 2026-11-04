package aaravgupta.cisum.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** cisum's palette, 1:1 with Aesthetics/UI/Extensions/Color+Extension.swift (light / dark). */
@Immutable
data class CisumColors(
    val primary: Color,
    val bg: Color,
    val surface: Color,
    val elevatedSurface: Color,
    val accent: Color,
    val yellow: Color,
    val dark: Color,
    val primaryText: Color,
    val secondaryText: Color,
    val isDark: Boolean,
) {
    val chromeSubtle get() = Color.White.copy(alpha = 0.1f)
    val chromeBorder get() = Color.White.copy(alpha = 0.2f)
    val chromeStrong get() = Color.White.copy(alpha = 0.32f)
    val trackActive get() = Color.White.copy(alpha = 0.9f)
    val trackInactive get() = Color.White.copy(alpha = 0.22f)
    val trackSecondary get() = Color.White.copy(alpha = 0.5f)
}

val LightCisum = CisumColors(
    primary = Color(0xFFFFFFFF),
    bg = Color(0xFFFDF6E3),
    surface = Color(0xFFEEE8D5),
    elevatedSurface = Color(0xFFFFF9EA),
    accent = Color(0xFFCBC2A5),
    yellow = Color(0xFFB58900),
    dark = Color(0xFF2B221B),
    primaryText = Color(0xFF151515),
    secondaryText = Color(0xFF68635B),
    isDark = false,
)

val DarkCisum = CisumColors(
    primary = Color(0xFF000000),
    bg = Color(0xFF101014),
    surface = Color(0xFF1C1C22),
    elevatedSurface = Color(0xFF272731),
    accent = Color(0xFFB8A879),
    yellow = Color(0xFFE6B84B),
    dark = Color(0xFFF2EBDC),
    primaryText = Color(0xFFF7F4EC),
    secondaryText = Color(0xFFB7B1A6),
    isDark = true,
)

val LocalCisumColors = staticCompositionLocalOf { LightCisum }
