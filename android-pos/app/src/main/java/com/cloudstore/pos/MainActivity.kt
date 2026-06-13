package com.cloudstore.pos

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.cloudstore.pos.data.CashierUserStore
import com.cloudstore.pos.data.OfflineQueueStore
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cloudstore.pos.data.PosRepository
import com.cloudstore.pos.data.TabletRegisterId
import com.cloudstore.pos.ui.PosScreen
import com.cloudstore.pos.ui.PosViewModel
import com.cloudstore.pos.ui.PosViewModelFactory
import com.cloudstore.pos.ui.theme.CloudStorePosTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val repository = PosRepository(baseUrl = BuildConfig.API_BASE_URL)
        val queueStore = OfflineQueueStore(applicationContext)
        val userStore = CashierUserStore(applicationContext)
        val registerId = TabletRegisterId.get(applicationContext)

        setContent {
            val viewModel: PosViewModel = viewModel(
                factory = PosViewModelFactory(
                    repository = repository,
                    queueStore = queueStore,
                    userStore = userStore,
                    registerId = registerId,
                )
            )
            CloudStorePosTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                    contentColor = MaterialTheme.colorScheme.onBackground,
                ) {
                    PosScreen(viewModel = viewModel)
                }
            }
        }
    }
}
