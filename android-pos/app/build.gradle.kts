import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
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

val devLanIp = detectLanIp() ?: "10.0.0.122"
val devApiPort = System.getenv("PORT") ?: "3000"
val devApiBaseUrl = "http://$devLanIp:$devApiPort/"
val releaseApiBaseUrl = System.getenv("RELEASE_API_BASE_URL") ?: devApiBaseUrl
println("[cloud-store-893] debug   API_BASE_URL = $devApiBaseUrl")
println("[cloud-store-893] release API_BASE_URL = $releaseApiBaseUrl")

android {
    namespace = "com.cloudstore.pos"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.cloudstore.pos"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        buildConfigField("String", "API_BASE_URL", "\"$devApiBaseUrl\"")
        // Decimal rates for totals line (e.g. 0.0825 = 8.25%). Override per build type if needed.
        buildConfigField("String", "POS_SALES_FEE_RATE", "\"0.0\"")
        buildConfigField("String", "POS_TAX_RATE", "\"0.0\"")
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
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
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
