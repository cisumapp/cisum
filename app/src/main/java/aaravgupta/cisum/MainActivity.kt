package aaravgupta.cisum

import android.os.Bundle
import dagger.hilt.android.AndroidEntryPoint
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import aaravgupta.cisum.perf.Perf
import aaravgupta.cisum.ui.theme.cisumTheme

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Perf.mark("activity.onCreate")
        Perf.installFrameMetrics(this)
        Perf.glassEnabled = intent.getBooleanExtra("glass", true)

        enableEdgeToEdge()
        setContent {
            cisumTheme {
                cisumApp()
            }
        }
    }
}