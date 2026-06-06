import java.io.ByteArrayOutputStream
import java.util.Properties
import java.util.concurrent.TimeUnit

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ── API_BASE_URL auto-detection ───────────────────────────────────────────────
// Resolves the dev backend URL at Gradle configuration time:
//   1. LAN_IP env var (manual override, e.g. `LAN_IP=192.168.1.50 ./gradlew ...`)
//   2. macOS `ipconfig getifaddr en0` (Wi-Fi / primary)
//   3. macOS `ipconfig getifaddr en1` (fallback for USB-C ethernet setups)
//   4. Hardcoded fallback so non-mac CI / Linux builds still compile.
//
// Override the release value with RELEASE_API_BASE_URL when shipping to cloud.
fun detectLanIp(): String? {
    System.getenv("LAN_IP")?.takeIf { it.isNotBlank() }?.let { return it }
    for (iface in listOf("en0", "en1")) {
        try {
            val out = ByteArrayOutputStream()
            val proc = ProcessBuilder("ipconfig", "getifaddr", iface)
                .redirectErrorStream(true)
                .start()
            proc.inputStream.copyTo(out)
            val finished = proc.waitFor(2, TimeUnit.SECONDS)
            if (finished && proc.exitValue() == 0) {
                val ip = out.toString(Charsets.UTF_8.name()).trim()
                if (ip.isNotEmpty()) return ip
            } else if (!finished) {
                proc.destroyForcibly()
            }
        } catch (_: Exception) {
            // ipconfig is mac-only; ignore on Linux/Windows.
        }
    }
    return null
}

val devLanIp = detectLanIp()
val devLanIpResolved = devLanIp ?: "oci.cloudstore893.com"
if (devLanIp == null) {
    println(
        "[cloud-store-893] WARNING: could not detect LAN IP — debug API_BASE_URL defaults to $devLanIpResolved. " +
            "For local dev set LAN_IP (e.g. LAN_IP=192.168.1.10 ./gradlew :app:assembleDebug).",
    )
}
val devApiPort = System.getenv("PORT") ?: "3000"
val devApiBaseUrl = "http://$devLanIpResolved:$devApiPort/"
val releaseApiBaseUrl = System.getenv("RELEASE_API_BASE_URL") ?: devApiBaseUrl
println("[cloud-store-893] debug   API_BASE_URL = $devApiBaseUrl")
println("[cloud-store-893] release API_BASE_URL = $releaseApiBaseUrl")

// ── POS totals (sales fee + tax) from android-pos/pos.properties ─────────────
val posPropertiesFile = rootProject.file("pos.properties")
val posProperties = Properties()
if (posPropertiesFile.exists()) {
    posPropertiesFile.inputStream().use { posProperties.load(it) }
} else {
    println("[cloud-store-893] pos.properties not found — using default rates 0.0")
}

fun posRate(key: String, default: String = "0.0"): String {
    val raw = posProperties.getProperty(key)?.trim().orEmpty()
    val value = if (raw.isEmpty()) default else raw
    val rate = value.toDoubleOrNull()
        ?: throw GradleException("pos.properties: $key must be a decimal rate (e.g. 0.0825), got \"$value\"")
    if (rate < 0.0 || rate > 1.0) {
        throw GradleException("pos.properties: $key must be between 0 and 1 (decimal rate), got $rate")
    }
    return value
}

val posSalesFeeRate = posRate("pos.sales.fee.rate")
val posTaxRate = posRate("pos.tax.rate")
println("[cloud-store-893] POS_SALES_FEE_RATE = $posSalesFeeRate")
println("[cloud-store-893] POS_TAX_RATE       = $posTaxRate")

android {
    namespace = "com.cloudstore.pos"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.cloudstore.pos"
        minSdk = 26
        targetSdk = 34
        versionCode = 5
        versionName = "1.4"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        buildConfigField("String", "API_BASE_URL", "\"$devApiBaseUrl\"")
        // Decimal rates from android-pos/pos.properties (e.g. 0.0825 = 8.25%).
        buildConfigField("String", "POS_SALES_FEE_RATE", "\"$posSalesFeeRate\"")
        buildConfigField("String", "POS_TAX_RATE", "\"$posTaxRate\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            buildConfigField("String", "API_BASE_URL", "\"$releaseApiBaseUrl\"")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.06.00")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.3")
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    implementation(composeBom)
    androidTestImplementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")

    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-moshi:2.11.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.squareup.moshi:moshi-kotlin:1.15.1")
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
    implementation("com.google.mlkit:barcode-scanning:17.2.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("junit:junit:4.13.2")
}
