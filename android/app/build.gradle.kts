import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional publisher signing. Never commit key.properties or the keystore.
val signingProperties = Properties().apply {
    val signingFile = rootProject.file("key.properties")
    if (signingFile.isFile) signingFile.inputStream().use { load(it) }
}
val signingKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val configuredSigningKeys = signingKeys.filter { !signingProperties.getProperty(it).isNullOrBlank() }
if (configuredSigningKeys.isNotEmpty() && configuredSigningKeys.size != signingKeys.size) {
    error("android/key.properties is incomplete. Provide all four signing properties or remove the file for QA/debug signing.")
}
val hasPublisherSigning = configuredSigningKeys.size == signingKeys.size
val publisherKeystore = signingProperties.getProperty("storeFile")?.let { rootProject.file(it) }
if (hasPublisherSigning && (publisherKeystore == null || !publisherKeystore.isFile)) {
    error("The keystore configured by android/key.properties does not exist. Check storeFile relative to the android directory.")
}

android {
    namespace = "com.amitar.amitar_gallery_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.amitar.amitar_gallery_player"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("publisherRelease") {
            if (hasPublisherSigning) {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = publisherKeystore
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // CI/QA remains buildable; distribution requires the publisher key.
            signingConfig = if (hasPublisherSigning) {
                signingConfigs.getByName("publisherRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
