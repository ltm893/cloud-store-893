package com.cloudstore.pos.ui

import android.os.SystemClock
import android.util.Log
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BrightnessHigh
import androidx.compose.material.icons.filled.BrightnessLow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.roundToInt

private const val TAG = "PosBarcodeScanner"

/** Reticle drawn on the live camera feed so it stays visible in both themes. */
private val ScanWindowColor = Color(0xFFFF9800)

@Composable
fun BarcodeScannerDialog(
    onBarcodeDetected: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var zoom by remember { mutableFloatStateOf(1f) }
    var exposure by remember { mutableFloatStateOf(0f) }
    var camera by remember { mutableStateOf<Camera?>(null) }

    LaunchedEffect(zoom, camera) {
        val active = camera ?: return@LaunchedEffect
        val maxZoom = active.cameraInfo.zoomState.value?.maxZoomRatio ?: 5f
        active.cameraControl.setZoomRatio(zoom.coerceIn(1f, minOf(5f, maxZoom)))
    }

    LaunchedEffect(exposure, camera) {
        val active = camera ?: return@LaunchedEffect
        val state = active.cameraInfo.exposureState
        if (!state.isExposureCompensationSupported) return@LaunchedEffect
        val step = state.exposureCompensationStep.toFloat()
        if (step <= 0f) return@LaunchedEffect
        val index = (exposure / step).roundToInt().coerceIn(
            state.exposureCompensationRange.lower,
            state.exposureCompensationRange.upper
        )
        active.cameraControl.setExposureCompensationIndex(index)
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "Scan barcode",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onBackground,
                        modifier = Modifier.padding(start = 12.dp),
                    )
                    TextButton(onClick = onDismiss) {
                        Text("Close")
                    }
                }
                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    BarcodeCameraPreview(
                        onCameraReady = { camera = it },
                        onBarcodeDetected = onBarcodeDetected,
                    )
                    BarcodeScanWindowOverlay()
                }
                BarcodeMagnifierBar(
                    zoom = zoom,
                    onZoom = { zoom = it.coerceIn(1f, 5f) },
                    exposure = exposure,
                    onExposure = { exposure = it.coerceIn(-2f, 2f) },
                )
            }
        }
    }
}

@Composable
private fun BarcodeMagnifierBar(
    zoom: Float,
    onZoom: (Float) -> Unit,
    exposure: Float,
    onExposure: (Float) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.55f))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(onClick = { onZoom(zoom - 0.5f) }) {
                Icon(Icons.Filled.Remove, contentDescription = "Zoom out", tint = Color.White)
            }
            Slider(
                value = zoom,
                onValueChange = onZoom,
                valueRange = 1f..5f,
                modifier = Modifier.weight(1f),
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color.White.copy(alpha = 0.35f),
                ),
            )
            IconButton(onClick = { onZoom(zoom + 0.5f) }) {
                Icon(Icons.Filled.Add, contentDescription = "Zoom in", tint = Color.White)
            }
            Text(
                text = String.format("%.1f×", zoom),
                color = Color.White,
                fontSize = 12.sp,
                modifier = Modifier.width(40.dp),
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(onClick = { onExposure(exposure - 0.5f) }) {
                Icon(Icons.Filled.BrightnessLow, contentDescription = "Darken", tint = Color.White)
            }
            Slider(
                value = exposure,
                onValueChange = onExposure,
                valueRange = -2f..2f,
                modifier = Modifier.weight(1f),
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color.White.copy(alpha = 0.35f),
                ),
            )
            IconButton(onClick = { onExposure(exposure + 0.5f) }) {
                Icon(Icons.Filled.BrightnessHigh, contentDescription = "Brighten", tint = Color.White)
            }
            Text(
                text = String.format("%+.1f", exposure),
                color = Color.White,
                fontSize = 12.sp,
                modifier = Modifier.width(40.dp),
            )
        }
        Text(
            text = "Place barcode in the window",
            color = Color.White,
            fontSize = 16.sp,
        )
    }
}

@Composable
private fun BarcodeScanWindowOverlay() {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val window = barcodeScanWindow(size)
        val dim = Path().apply {
            addRect(Rect(Offset.Zero, size))
            addRoundRect(
                androidx.compose.ui.geometry.RoundRect(
                    window,
                    CornerRadius(16f, 16f),
                ),
            )
            fillType = PathFillType.EvenOdd
        }
        drawPath(dim, Color.Black.copy(alpha = 0.45f))
        drawRoundRect(
            color = ScanWindowColor,
            topLeft = window.topLeft,
            size = window.size,
            cornerRadius = CornerRadius(16f, 16f),
            style = Stroke(width = 6f),
        )
    }
}

/** Wide window centered slightly above the middle, matching a bottle barcode. */
private fun barcodeScanWindow(size: Size): Rect {
    val width = size.width * 0.78f
    val height = minOf(maxOf(size.height * 0.20f, 96f), width / 2.2f)
    val left = (size.width - width) / 2f
    val top = (size.height - height) / 2f - size.height * 0.05f
    return Rect(Offset(left, top), Size(width, height))
}

@Composable
private fun BarcodeCameraPreview(
    onCameraReady: (Camera) -> Unit,
    onBarcodeDetected: (String) -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val detected = remember { AtomicBoolean(false) }
    val options = remember {
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_UPC_A,
                Barcode.FORMAT_UPC_E,
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_PDF417,
                Barcode.FORMAT_QR_CODE,
            )
            .build()
    }
    val scanner = remember { BarcodeScanning.getClient(options) }
    val nonRetailSince = remember { AtomicLong(0L) }

    AndroidView(
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                imageAnalysis.setAnalyzer(executor) { imageProxy ->
                    processImage(imageProxy, scanner, detected, nonRetailSince, onBarcodeDetected)
                }
                try {
                    cameraProvider.unbindAll()
                    val bound = cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        imageAnalysis,
                    )
                    onCameraReady(bound)
                } catch (e: Exception) {
                    Log.e(TAG, "Camera bind failed: ${e.message}")
                }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
        modifier = Modifier.fillMaxSize(),
    )

    DisposableEffect(Unit) {
        onDispose {
            scanner.close()
            executor.shutdown()
            runCatching { ProcessCameraProvider.getInstance(context).get().unbindAll() }
        }
    }
}

@androidx.annotation.OptIn(androidx.camera.core.ExperimentalGetImage::class)
private fun processImage(
    imageProxy: ImageProxy,
    scanner: com.google.mlkit.vision.barcode.BarcodeScanner,
    detected: AtomicBoolean,
    nonRetailSince: AtomicLong,
    onDetected: (String) -> Unit,
) {
    val mediaImage = imageProxy.image
    if (mediaImage != null) {
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                val selection = ProductBarcode.preferred(barcodes.mapNotNull { it.toProductRead() })
                    ?: return@addOnSuccessListener
                val now = SystemClock.elapsedRealtime()
                val pending = nonRetailSince.get().takeIf { it != 0L }
                when (ProductBarcode.decide(selection.symbology, pending, now)) {
                    ProductBarcode.Decision.Accept -> {
                        if (detected.compareAndSet(false, true)) {
                            Log.d(TAG, selection.logMessage())
                            onDetected(selection.value)
                        }
                    }
                    ProductBarcode.Decision.Wait -> nonRetailSince.compareAndSet(0L, now)
                }
            }
            .addOnCompleteListener { imageProxy.close() }
    } else {
        imageProxy.close()
    }
}

private fun Barcode.toProductRead(): ProductBarcode.Read? {
    val value = rawValue ?: return null
    val symbology = when (format) {
        Barcode.FORMAT_UPC_A -> ProductBarcode.Symbology.UPC_A
        Barcode.FORMAT_UPC_E -> ProductBarcode.Symbology.UPC_E
        Barcode.FORMAT_EAN_13 -> ProductBarcode.Symbology.EAN_13
        Barcode.FORMAT_EAN_8 -> ProductBarcode.Symbology.EAN_8
        Barcode.FORMAT_CODE_128 -> ProductBarcode.Symbology.CODE_128
        Barcode.FORMAT_PDF417 -> ProductBarcode.Symbology.PDF417
        Barcode.FORMAT_QR_CODE -> ProductBarcode.Symbology.QR
        else -> ProductBarcode.Symbology.OTHER
    }
    return ProductBarcode.Read(symbology, value)
}
