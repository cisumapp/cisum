package aaravgupta.cisum.baselineprofile

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The paths users hit first: cold start, Home and Discover scrolling, a search, the player.
 * Their code is AOT-compiled from the profile instead of being interpreted then JIT'd.
 * Run: ./gradlew :app:generateReleaseBaselineProfile (a device or emulator must be connected).
 */
@RunWith(AndroidJUnit4::class)
class BaselineProfileGenerator {
    @get:Rule val rule = BaselineProfileRule()

    @Test
    fun generate() = rule.collect(packageName = "aaravgupta.cisum", includeInStartupProfile = true) {
        pressHome()
        startActivityAndWait()
        device.wait(Until.hasObject(By.text("Top Songs")), 15_000)

        device.findObject(By.scrollable(true))?.fling(Direction.DOWN)
        device.findObject(By.text("Discover"))?.click()
        device.wait(Until.hasObject(By.textStartsWith("#1")), 15_000)
        device.findObject(By.scrollable(true))?.fling(Direction.DOWN)

        device.findObject(By.desc("Search"))?.click() ?: device.findObject(By.text("Library"))?.click()
        device.waitForIdle()
    }
}
