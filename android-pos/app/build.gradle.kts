import java.io.ByteArrayOutputStream
import java.util.Properties
import java.util.concurrent.TimeUnit

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ── API_BASE_URL auto-detection ───────────────────────────────────────────────
// Priority:
//   1. RELEASE_API_BASE_URL (set by RebuildReinstall.sh for OCI HTTPS)
//   2. LAN_IP / ipconfig — private RFC1918 → http://IP:PORT (local npm run dev:up)
//   3. Default OCI cloud → https://oci.cloudstore893.com/ (LB :443, no :3000)
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

fun isPrivateLanHost(host: String): Boolean {
    if (host == "127.0.0.1" || host.equals("localhost", ignoreCase = true)) return true
    if (host.startsWith("10.")) return true
    if (host.startsWith("192.168.")) return true
    return host.matches(Regex("^172\\.(1[6-9]|2\\d|3[01])\\..+"))
}

fun normalizeApiBaseUrl(raw: String): String {
    val trimmed = raw.trim()
    return if (trimmed.endsWith("/")) trimmed else "$trimmed/"
}

val ociApiHost = "oci.cloudstore893.com"
val devApiPort = System.getenv("PORT") ?: "3000"
val devLanIp = detectLanIp()

val apiBaseUrl = System.getenv("RELEASE_API_BASE_URL")?.takeIf { it.isNotBlank() }?.let(::normalizeApiBaseUrl)
    ?: when {
        devLanIp != null && isPrivateLanHost(devLanIp) -> "http://$devLanIp:$devApiPort/"
        else -> {
            println(
                "[cloud-store-893] OCI default API_BASE_URL: https://$ociApiHost/ " +
                    "(HTTPS via LB). Local dev: USE_LOCAL=1 or LAN_IP=192.168.x.x",
            )
            "https://$ociApiHost/"
        }
    }

println("[cloud-store-893] API_BASE_URL = $apiBaseUrl")

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

        buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
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
            buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
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
    implementation("androidx.compose.material:material-icons-extended")
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
