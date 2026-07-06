package com.cloudstore.lister.ui.tabs

import android.annotation.SuppressLint
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Dialpad
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.cloudstore.lister.ui.theme.ListerBackground
import com.cloudstore.lister.ui.theme.ListerHighlight
import com.cloudstore.lister.ui.theme.ListerMuted
import com.cloudstore.lister.ui.theme.ListerPrimary
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

enum class InputRoute {
    Hub,
    Manual,
    Scanner,
}

@Composable
fun InputTab(
    hostLabel: String,
    inputText: String,
    route: InputRoute,
    onRouteChange: (InputRoute) -> Unit,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    onClear: () -> Unit,
    onLookup: () -> Unit,
    onBarcode: (String) -> Unit,
    onImportCsv: () -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(ListerBackground),
    ) {
        when (route) {
            InputRoute.Hub -> InputHubScreen(
                hostLabel = hostLabel,
                onBarcode = { onRouteChange(InputRoute.Scanner) },
                onManual = { onRouteChange(InputRoute.Manual) },
                onImportCsv = onImportCsv,
            )
            InputRoute.Manual -> ManualInputScreen(
                inputText = inputText,
                onDigit = onDigit,
                onBackspace = onBackspace,
                onClear = onClear,
                onLookup = onLookup,
            )
            InputRoute.Scanner -> BarcodeScannerScreen(
                onBarcode = onBarcode,
                onCancel = { onRouteChange(InputRoute.Hub) },
            )
        }
    }
}

@Composable
private fun InputHubScreen(
    hostLabel: String,
    onBarcode: () -> Unit,
    onManual: () -> Unit,
    onImportCsv: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        InputHubButton(
            label = "Barcode Scanner",
            icon = Icons.Default.QrCodeScanner,
            onClick = onBarcode,
        )
        Spacer(Modifier.height(20.dp))
        InputHubButton(
            label = "Manual",
            icon = Icons.Default.Dialpad,
            onClick = onManual,
        )
        Spacer(Modifier.height(20.dp))
        InputHubButton(
            label = "Import CSV",
            icon = Icons.Default.Description,
            onClick = onImportCsv,
        )
        Spacer(Modifier.weight(1f))
        Text(
            text = hostLabel,
            style = MaterialTheme.typography.bodySmall,
            color = ListerMuted,
            modifier = Modifier.padding(bottom = 12.dp),
        )
    }
}

@Composable
private fun InputHubButton(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = ListerPrimary,
            contentColor = androidx.compose.ui.graphics.Color.White,
        ),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.padding(end = 12.dp))
        Text(label, style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
private fun ManualInputScreen(
    inputText: String,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    onClear: () -> Unit,
    onLookup: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(64.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(ListerHighlight),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = inputText.ifEmpty { "Enter ID or barcode" },
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                fontSize = 28.sp,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onBackground,
            )
        }
        NumberPad(
            onDigit = onDigit,
            onBackspace = onBackspace,
            onClear = onClear,
            onEnter = onLookup,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun NumberPad(
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    onClear: () -> Unit,
    onEnter: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(15.dp)) {
        listOf(
            listOf('1', '2', '3'),
            listOf('4', '5', '6'),
            listOf('7', '8', '9'),
        ).forEach { row ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                row.forEach { key ->
                    NumpadKey(label = key.toString()) { onDigit(key) }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NumpadKey(icon = Icons.AutoMirrored.Filled.Backspace, onClick = onBackspace)
            NumpadKey(label = "0") { onDigit('0') }
            NumpadKey(label = "C", onClick = onClear)
        }
        Button(
            onClick = onEnter,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp)
                .height(45.dp),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = ListerPrimary,
                contentColor = androidx.compose.ui.graphics.Color.White,
            ),
        ) {
            Text("Lookup", fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun NumpadKey(
    label: String? = null,
    icon: ImageVector? = null,
    onClick: () -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.size(80.dp),
        shape = CircleShape,
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = ListerHighlight,
            contentColor = ListerPrimary,
        ),
        border = null,
    ) {
        when {
            icon != null -> Icon(icon, contentDescription = label, modifier = Modifier.size(28.dp))
            label != null -> Text(label, fontSize = 22.sp, fontWeight = FontWeight.Normal)
        }
    }
}

@Composable
private fun BarcodeScannerScreen(
    onBarcode: (String) -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        BarcodeCamera(Modifier.weight(1f), onBarcode)
        OutlinedButton(
            onClick = onCancel,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = ListerPrimary),
        ) {
            Text("Cancel")
        }
    }
}

@SuppressLint("UnsafeOptInUsageError")
@Composable
private fun BarcodeCamera(modifier: Modifier, onBarcode: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember { PreviewView(context) }
    val executor = remember { Executors.newSingleThreadExecutor() }
    val scanner = remember { BarcodeScanning.getClient() }
    val delivered = remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val provider = future.get()
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
            val analysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(1280, 720))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            analysis.setAnalyzer(executor) { proxy ->
                val media = proxy.image
                if (media != null && !delivered.value) {
                    val image = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
                    scanner.process(image)
                        .addOnSuccessListener { codes ->
                            val value = codes.firstNotNullOfOrNull { barcode ->
                                barcode.rawValue?.takeIf { it.isNotBlank() }
                            }
                            if (value != null && !delivered.value) {
                                delivered.value = true
                                onBarcode(value)
                            }
                        }
                        .addOnCompleteListener { proxy.close() }
                } else {
                    proxy.close()
                }
            }
            provider.unbindAll()
            provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            executor.shutdown()
            runCatching { ProcessCameraProvider.getInstance(context).get().unbindAll() }
        }
    }

    AndroidView(
        factory = { previewView },
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp)),
    )
}
