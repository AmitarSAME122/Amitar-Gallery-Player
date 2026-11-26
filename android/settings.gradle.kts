pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localProperties = file("local.properties")
        require(localProperties.isFile) {
            "android/local.properties is missing. Run Flutter tooling from the project root first."
        }
        localProperties.inputStream().use { properties.load(it) }
        val path = properties.getProperty("flutter.sdk")
        require(!path.isNullOrBlank()) {
            "flutter.sdk is not configured in android/local.properties. Run `flutter pub get` first."
        }
        path
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // Resolve Google's Android Gradle Plugin from its canonical module coordinate.
    // This avoids depending on the com.android.application plugin-marker POM,
    // which some Google Maven mirrors/proxies fail to expose even when the AGP
    // implementation artifact itself is available.
    resolutionStrategy {
        eachPlugin {
            if (requested.id.namespace == "com.android") {
                useModule("com.android.tools.build:gradle:${requested.version}")
            }
        }
    }

    // Optional trusted mirror for networks that cannot reach Google Maven.
    // Set AMITAR_GOOGLE_MAVEN_MIRROR to an HTTPS Maven mirror you explicitly trust.
    val googleMavenMirror = System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")?.trim().orEmpty()
    if (googleMavenMirror.isNotEmpty()) {
        require(googleMavenMirror.startsWith("https://", ignoreCase = true)) {
            "AMITAR_GOOGLE_MAVEN_MIRROR must use HTTPS."
        }
    }

    repositories {
        if (googleMavenMirror.isNotEmpty()) {
            maven {
                name = "AmitarTrustedGoogleMavenMirror"
                url = uri(googleMavenMirror)
            }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

rootProject.name = "AmitarGalleryPlayer"
include(":app")
