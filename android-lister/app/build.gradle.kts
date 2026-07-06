import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

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
// Only auto-detect LAN when building without RELEASE_API_BASE_URL (e.g. plain ./gradlew).
// RebuildReinstall.sh always exports RELEASE_API_BASE_URL (OCI by default).
val devLanIp = detectLanIp()

val apiBaseUrl = System.getenv("RELEASE_API_BASE_URL")?.takeIf { it.isNotBlank() }?.let(::normalizeApiBaseUrl)
    ?: when {
        devLanIp != null && isPrivateLanHost(devLanIp) -> "http://$devLanIp:$devApiPort/"
        else -> {
            println(
                "[cloud-store-893] OCI default android-lister API_BASE_URL: https://$ociApiHost/ " +
                    "(use RebuildReinstall.sh or RELEASE_API_BASE_URL for tablet installs)",
            )
            "https://$ociApiHost/"
        }
    }

println("[cloud-store-893] android-lister API_BASE_URL = $apiBaseUrl")

android {
    namespace = "com.cloudstore.lister"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.cloudstore.lister"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
        buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
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
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.navigation:navigation-compose:2.7.7")

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
    testImplementation("junit:junit:4.13.2")
}
