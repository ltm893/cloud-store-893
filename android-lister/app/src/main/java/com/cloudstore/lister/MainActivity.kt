package com.cloudstore.lister

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cloudstore.lister.ui.ListerAppScreen
import com.cloudstore.lister.ui.ListerViewModel
import com.cloudstore.lister.ui.theme.CloudStoreListerTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            CloudStoreListerTheme {
                val vm: ListerViewModel = viewModel(factory = ListerViewModel.Factory(this))
                ListerAppScreen(vm)
            }
        }
    }
}
