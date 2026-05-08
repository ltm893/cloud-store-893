package com.cloudstore.pos

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.cloudstore.pos.data.OfflineQueueStore
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.ui.PosScreen
import com.cloudstore.pos.ui.PosViewModel
import com.cloudstore.pos.ui.PosViewModelFactory

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val repository = PosRepository(baseUrl = BuildConfig.API_BASE_URL)
        val queueStore = OfflineQueueStore(applicationContext)

        setContent {
            val viewModel: PosViewModel = viewModel(
                factory = PosViewModelFactory(
                    repository = repository,
                    queueStore = queueStore,
                    expectedPin = BuildConfig.CASHIER_PIN,
                )
            )
            MaterialTheme {
                Surface {
                    PosScreen(viewModel = viewModel)
                }
            }
        }
    }
}
