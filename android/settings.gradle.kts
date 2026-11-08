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

    resolutionStrategy {
        eachPlugin {
            if (requested.id.namespace == "com.android") {
                useModule("com.android.tools.build:gradle:${requested.version}")
            }
        }
    }

    repositories {
        // ۱. میرورهای ایرانی (اولویت اول برای شبکه‌های با محدودیت)
        maven { url = uri("https://maven.myket.ir") }
        maven { url = uri("https://maven.devneeds.ir") }
        maven { url = uri("https://gradle.iranrepo.ir") }
        maven { url = uri("https://gradle.jamko.ir") }
        maven { url = uri("https://en-mirror.ir") }
        maven { url = uri("https://archive.ito.gov.ir/gradle/maven-plugin/") }

        // ۲. میرورهای چینی Aliyun (با آدرس‌های اصلاح‌شده)
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }

        // ۳. میرور Runflare (گزینه جایگزین)
        maven { url = uri("https://mirror-maven.runflare.com/android/maven2/") }
        maven { url = uri("https://mirror-maven.runflare.com/maven2/") }
        maven { url = uri("https://mirror-maven.runflare.com/gradle-plugins/") }

        // ۴. میرور سفارشی (در صورت تنظیم متغیر محیطی AMITAR_GOOGLE_MAVEN_MIRROR)
        val googleMavenMirror = System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")?.trim().orEmpty()
        if (googleMavenMirror.isNotEmpty()) {
            require(googleMavenMirror.startsWith("https://", ignoreCase = true)) {
                "AMITAR_GOOGLE_MAVEN_MIRROR must use HTTPS."
            }
            maven {
                name = "AmitarTrustedGoogleMavenMirror"
                url = uri(googleMavenMirror)
            }
        }

        // ۵. مخازن رسمی (به عنوان fallback نهایی)
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.2" apply false
    // نسخه Kotlin به 2.2.21 ارتقا یافت تا مشکل عدم وجود نسخه 2.2.20 حل شود
    id("org.jetbrains.kotlin.android") version "2.2.21" apply false
}

rootProject.name = "AmitarGalleryPlayer"
include(":app")