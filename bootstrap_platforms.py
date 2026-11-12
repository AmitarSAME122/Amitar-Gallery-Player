#!/usr/bin/env python3
"""Generate Flutter native/web host projects and apply idempotent app settings."""
from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = "android,ios,web,windows,macos,linux"
APP_ENTRYPOINT = ROOT / "lib/AmitarGalleryPlayer.dart"
# Gradle 8.14.6's published wrapper checksum does not match the wrapper JAR
# stored at the v8.14.6 tag. Gradle's release8x branch was updated in commit
# c27417f with the exact release JAR; pin that immutable source and verify it
# against Gradle's published SHA-256 before it can enter a build.
GRADLE_WRAPPER_SOURCE_COMMIT = "c27417f"
GRADLE_WRAPPER_URL = (
    "https://raw.githubusercontent.com/gradle/gradle/"
    f"{GRADLE_WRAPPER_SOURCE_COMMIT}/gradle/wrapper/gradle-wrapper.jar"
)
GRADLE_WRAPPER_SHA256 = "ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0"
GRADLE_WRAPPER_DOWNLOAD_TIMEOUT_SECONDS = 60
GRADLE_WRAPPER_MAX_BYTES = 1024 * 1024
GRADLE_WRAPPER_DOWNLOAD_ATTEMPTS = 3
GRADLE_WRAPPER_RETRYABLE_HTTP_STATUS = {408, 425, 429, 500, 502, 503, 504}
ANDROID_PERMISSIONS = (
    '    <uses-permission android:name="android.permission.INTERNET" />',
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />',
)


def run(command: list[str], *, cwd: Path = ROOT) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def ensure_android_manifest() -> None:
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        raise FileNotFoundError(f"Flutter did not generate {manifest.relative_to(ROOT)}")
    content = manifest.read_text(encoding="utf-8")
    for permission in ANDROID_PERMISSIONS:
        match = re.search(r'android:name="([^"]+)"', permission)
        if match is None:
            raise RuntimeError(f"Malformed Android permission declaration: {permission}")
        name = match.group(1)
        if f'android:name="{name}"' not in content:
            content = re.sub(r"(<manifest\b[^>]*>)", r"\1\n" + permission, content, count=1)
    content = re.sub(r'android:label="[^"]+"', 'android:label="AmitarGalleryPlayer"', content, count=1)
    manifest.write_text(content, encoding="utf-8")


def set_podfile_platform(path: Path, platform: str, version: str) -> None:
    if not path.exists():
        return
    content = path.read_text(encoding="utf-8")
    pattern = rf"(?m)^[ \t]*#?[ \t]*platform[ \t]+:{re.escape(platform)},[ \t]*[\'\"][^\'\"]+[\'\"][ \t]*$"
    replacement = f"platform :{platform}, '{version}'"
    if re.search(pattern, content):
        content = re.sub(pattern, replacement, content, count=1)
    else:
        content = replacement + "\n\n" + content
    path.write_text(content, encoding="utf-8")


def update_plist(path: Path, values: dict[str, object]) -> None:
    if not path.exists():
        return
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    data.update(values)
    with path.open("wb") as handle:
        plistlib.dump(data, handle, fmt=plistlib.FMT_XML, sort_keys=False)


def update_entitlements(path: Path) -> None:
    if not path.exists():
        return
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    data.update({
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
        "com.apple.security.files.user-selected.read-write": True,
        "com.apple.security.personal-information.photos-library": True,
    })
    with path.open("wb") as handle:
        plistlib.dump(data, handle, fmt=plistlib.FMT_XML, sort_keys=False)


def set_xcode_deployment_target(path: Path, setting: str, version: str) -> None:
    if not path.exists():
        return
    content = path.read_text(encoding="utf-8")
    content, count = re.subn(
        rf"({re.escape(setting)}\s*=\s*)[0-9.]+;",
        rf"\g<1>{version};",
        content,
    )
    if count:
        path.write_text(content, encoding="utf-8")



def write_if_changed(path: Path, content: str) -> None:
    """Write generated configuration only when it differs (safe to rerun)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.is_file() or path.read_text(encoding="utf-8") != content:
        path.write_text(content, encoding="utf-8")


def _is_verified_gradle_wrapper_jar(path: Path) -> bool:
    """Return True only for the exact, structurally valid Gradle 8.14.6 JAR."""
    if not path.is_file() or path.stat().st_size == 0:
        return False
    try:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != GRADLE_WRAPPER_SHA256:
            return False
        with zipfile.ZipFile(path) as archive:
            return "org/gradle/wrapper/GradleWrapperMain.class" in archive.namelist()
    except (OSError, zipfile.BadZipFile):
        return False


def ensure_verified_gradle_wrapper_jar() -> None:
    """Install the official Gradle 8.14.6 Wrapper JAR and verify it before use.

    Gradle publishes the wrapper JAR checksum, but the 8.14.6 JAR at the
    ``v8.14.6`` source tag differs from that published release checksum. The
    matching release JAR is present in Gradle commit ``c27417f``. Downloading
    from that immutable source avoids the non-existent standalone distribution
    JAR URL; the SHA-256 check remains the trust boundary.

    A valid existing JAR is reused. A failed download or validation never
    replaces an existing file with untrusted bytes.
    """
    wrapper_jar = ROOT / "android/gradle/wrapper/gradle-wrapper.jar"
    if _is_verified_gradle_wrapper_jar(wrapper_jar):
        print("Verified Gradle 8.14.6 Wrapper JAR already exists.", flush=True)
        return

    wrapper_jar.parent.mkdir(parents=True, exist_ok=True)
    temporary = wrapper_jar.with_name(wrapper_jar.name + ".download")
    request = urllib.request.Request(
        GRADLE_WRAPPER_URL,
        headers={"User-Agent": "AmitarGalleryPlayer-build-bootstrap/2.0"},
    )

    try:
        payload: bytes | None = None
        last_network_error: BaseException | None = None
        for attempt in range(1, GRADLE_WRAPPER_DOWNLOAD_ATTEMPTS + 1):
            try:
                with urllib.request.urlopen(
                    request, timeout=GRADLE_WRAPPER_DOWNLOAD_TIMEOUT_SECONDS
                ) as response:
                    payload = response.read(GRADLE_WRAPPER_MAX_BYTES + 1)
                break
            except urllib.error.HTTPError as error:
                if (
                    error.code not in GRADLE_WRAPPER_RETRYABLE_HTTP_STATUS
                    or attempt == GRADLE_WRAPPER_DOWNLOAD_ATTEMPTS
                ):
                    raise
                last_network_error = error
            except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                if attempt == GRADLE_WRAPPER_DOWNLOAD_ATTEMPTS:
                    raise
                last_network_error = error

            delay_seconds = min(2 ** (attempt - 1), 4)
            print(
                f"Gradle Wrapper download attempt {attempt} failed; "
                f"retrying in {delay_seconds}s: {last_network_error}",
                flush=True,
            )
            time.sleep(delay_seconds)

        if payload is None:
            raise RuntimeError(
                f"Gradle Wrapper download produced no response: {last_network_error}"
            )
        if not payload or len(payload) > GRADLE_WRAPPER_MAX_BYTES:
            raise RuntimeError(
                "Downloaded Gradle Wrapper JAR has an invalid size "
                f"({len(payload)} bytes; expected 1..{GRADLE_WRAPPER_MAX_BYTES})."
            )

        actual_hash = hashlib.sha256(payload).hexdigest()
        if actual_hash != GRADLE_WRAPPER_SHA256:
            raise RuntimeError(
                "Downloaded Gradle Wrapper JAR failed SHA-256 verification: "
                f"expected {GRADLE_WRAPPER_SHA256}, got {actual_hash}."
            )

        temporary.write_bytes(payload)
        if not _is_verified_gradle_wrapper_jar(temporary):
            raise RuntimeError(
                "Downloaded Gradle Wrapper JAR is not a valid archive or "
                "does not contain GradleWrapperMain.class."
            )

        temporary.replace(wrapper_jar)
        print(
            "Installed and SHA-256 verified Gradle 8.14.6 Wrapper JAR "
            f"from Gradle commit {GRADLE_WRAPPER_SOURCE_COMMIT}.",
            flush=True,
        )
    except (OSError, urllib.error.URLError, zipfile.BadZipFile, RuntimeError) as error:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise RuntimeError(
            "Could not install the verified Gradle 8.14.6 Wrapper JAR. "
            f"Source: {GRADLE_WRAPPER_URL}. Check outbound access to "
            "raw.githubusercontent.com and rerun `python tool/bootstrap_platforms.py`. "
            "An unverified or checksum-mismatched Wrapper will never be used. "
            f"Details: {error}"
        ) from error


def configure_android_gradle() -> None:
    """Install a reproducible Flutter/AGP/Kotlin Gradle host configuration."""
    write_if_changed(ROOT / "android/settings.gradle.kts", '''pluginManagement {
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
''')
    write_if_changed(ROOT / "android/build.gradle.kts", '''val googleMavenMirror = System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")?.trim().orEmpty()
if (googleMavenMirror.isNotEmpty()) {
    require(googleMavenMirror.startsWith("https://", ignoreCase = true)) {
        "AMITAR_GOOGLE_MAVEN_MIRROR must use HTTPS."
    }
}

allprojects {
    repositories {
        if (googleMavenMirror.isNotEmpty()) {
            maven {
                name = "AmitarTrustedGoogleMavenMirror"
                url = uri(googleMavenMirror)
            }
        }
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
''')
    write_if_changed(ROOT / "android/app/build.gradle.kts", '''import java.util.Properties

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
''')
    write_if_changed(ROOT / "android/gradle/wrapper/gradle-wrapper.properties", '''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionSha256Sum=7988ed071b2a07900e2ec715fca15c6ab72bce6db433af301fa7fa7e9407bd24
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.6-bin.zip
networkTimeout=30000
retries=3
retryBackOffMs=1000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
''')
    write_if_changed(ROOT / "android/gradle.properties", '''org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=512m -Dfile.encoding=UTF-8
android.useAndroidX=true
org.gradle.caching=true
org.gradle.parallel=true
kotlin.incremental=true
''')

    old_main = ROOT / "android/app/src/main/kotlin/com/example/amitar_gallery_player/MainActivity.kt"
    main_activity = ROOT / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt"
    main_activity.parent.mkdir(parents=True, exist_ok=True)
    if old_main.is_file() and not main_activity.is_file():
        main_activity.write_text(
            old_main.read_text(encoding="utf-8").replace(
                "package com.example.amitar_gallery_player",
                "package com.amitar.amitar_gallery_player",
            ),
            encoding="utf-8",
        )
        old_main.unlink()
    elif not main_activity.is_file():
        main_activity.write_text(
            "package com.amitar.amitar_gallery_player\n\n"
            "import io.flutter.embedding.android.FlutterActivity\n\n"
            "class MainActivity : FlutterActivity()\n",
            encoding="utf-8",
        )
    if old_main.parent.exists():
        for parent in (old_main.parent, old_main.parent.parent, old_main.parent.parent.parent, old_main.parent.parent.parent.parent):
            try:
                parent.rmdir()
            except OSError:
                pass

def configure_apple_hosts() -> None:
    photo_text = (
        "AmitarGalleryPlayer uses your Photos library to display media you authorize."
    )
    save_text = (
        "AmitarGalleryPlayer saves edited image copies and captured video frames to your Photos library when authorized."
    )
    update_plist(ROOT / "ios/Runner/Info.plist", {
        "CFBundleDisplayName": "AmitarGalleryPlayer",
        "NSPhotoLibraryUsageDescription": photo_text,
        "NSPhotoLibraryAddUsageDescription": save_text,
    })
    update_plist(ROOT / "macos/Runner/Info.plist", {
        "CFBundleDisplayName": "AmitarGalleryPlayer",
        "NSPhotoLibraryUsageDescription": photo_text,
        "NSPhotoLibraryAddUsageDescription": save_text,
    })
    set_podfile_platform(ROOT / "ios/Podfile", "ios", "15.0")
    set_podfile_platform(ROOT / "macos/Podfile", "osx", "12.0")
    set_xcode_deployment_target(ROOT / "ios/Runner.xcodeproj/project.pbxproj", "IPHONEOS_DEPLOYMENT_TARGET", "15.0")
    set_xcode_deployment_target(ROOT / "macos/Runner.xcodeproj/project.pbxproj", "MACOSX_DEPLOYMENT_TARGET", "12.0")
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        update_entitlements(ROOT / "macos/Runner" / name)



def configure_linux_icon() -> None:
    """Install the Linux resource icon and wire it to the generated GTK window."""
    source = ROOT / "assets/icons/linux-256.png"
    linux_root = ROOT / "linux/runner/resources"
    if not (ROOT / "linux").is_dir():
        return
    if not source.is_file():
        raise FileNotFoundError(f"Missing Linux window icon source: {source}")
    linux_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, linux_root / "app_icon.png")

    runner = ROOT / "linux/runner/my_application.cc"
    if not runner.is_file():
        raise FileNotFoundError(f"Flutter Linux runner source is missing: {runner}")
    content = runner.read_text(encoding="utf-8")
    marker = "AmitarGalleryPlayer Linux window icon"
    if marker in content:
        return
    anchor = re.compile(
        r"(?m)^(?P<indent>[ \t]*)gtk_window_set_default_size\("
        r"(?P<window>[^,]+),[^\n]*\);[ \t]*$"
    )
    match = anchor.search(content)
    if match is None:
        raise RuntimeError(
            "Could not locate gtk_window_set_default_size() in the generated Linux runner; "
            "refusing to silently ship a default window icon."
        )
    window_expression = match.group("window").strip()
    indent = match.group("indent")
    icon_setup = (
        f'{indent}// {marker}; path is resolved from the installed executable, not cwd.\n'
        f'{indent}gchar* executable_path = g_file_read_link("/proc/self/exe", NULL);\n'
        f'{indent}if (executable_path != NULL) {{\n'
        f'{indent}  gchar* executable_dir = g_path_get_dirname(executable_path);\n'
        f'{indent}  gchar* icon_path = g_build_filename(\n'
        f'{indent}      executable_dir, "data", "flutter_assets", "assets",\n'
        f'{indent}      "icons", "linux-256.png", NULL);\n'
        f'{indent}  GError* icon_error = NULL;\n'
        f'{indent}  if (!gtk_window_set_icon_from_file(GTK_WINDOW({window_expression}),\n'
        f'{indent}                                    icon_path, &icon_error)) {{\n'
        f'{indent}    if (icon_error != NULL) {{\n'
        f'{indent}      g_warning("Unable to load AmitarGalleryPlayer window icon: %s",\n'
        f'{indent}                icon_error->message);\n'
        f'{indent}      g_error_free(icon_error);\n'
        f'{indent}    }}\n'
        f'{indent}  }}\n'
        f'{indent}  g_free(icon_path);\n'
        f'{indent}  g_free(executable_dir);\n'
        f'{indent}  g_free(executable_path);\n'
        f'{indent}}}\n'
    )
    end = match.end()
    content = content[:end] + "\n" + icon_setup.rstrip() + content[end:]
    runner.write_text(content, encoding="utf-8")


def _restore_project_file_snapshot(path: Path, original_bytes: bytes | None) -> None:
    """Atomically restore a tracked project file, including its prior absence."""
    if original_bytes is None:
        # Do not leave a newly generated file behind when it was absent before
        # bootstrap (for example, in a minimal fixture or a fresh checkout).
        if path.is_file():
            path.unlink()
        return
    if path.is_file() and path.read_bytes() == original_bytes:
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_name(f".{path.name}.restore.tmp")
    try:
        temporary_path.write_bytes(original_bytes)
        temporary_path.replace(path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def _capture_project_file_snapshots(
    *, preserve_android_activity: bool = False,
) -> list[tuple[Path, bytes | None]]:
    """Capture tracked Flutter files, optionally including the custom Activity.

    MainActivity contains the app's Android ContentResolver bridge. Preserve it
    around `flutter create`, but do not preserve its prior absence around the
    full bootstrap: configure_android_gradle() must be able to create a valid
    default Activity when a platform host is first generated.
    """
    paths = [ROOT / ".metadata", ROOT / "pubspec.lock"]
    if preserve_android_activity:
        paths.append(
            ROOT / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt"
        )
    return [(path, path.read_bytes() if path.is_file() else None) for path in paths]


def _restore_project_file_snapshots(snapshots: list[tuple[Path, bytes | None]]) -> None:
    """Restore all captured project files even when a later step raises."""
    for path, original_bytes in snapshots:
        _restore_project_file_snapshot(path, original_bytes)


def run_flutter_create_preserving_metadata() -> None:
    """Generate host projects without changing tracked metadata or dependency locks.

    Flutter scaffolding may update `.metadata` for the installed SDK. Guard the
    checked-in `pubspec.lock` as well: dependency resolution is deliberately
    deferred to the dedicated `flutter pub get` step in the CI workflow. Preserve
    the app-owned Android MainActivity integration too, even if `flutter create`
    rewrites the generated host Activity. All snapshots are restored byte-for-byte
    even if `flutter create` fails.
    """
    snapshots = _capture_project_file_snapshots(preserve_android_activity=True)
    try:
        run([
            "flutter", "create", "--org=com.amitar",
            "--project-name=amitar_gallery_player",
            f"--platforms={PLATFORMS}", "--no-pub", ".",
        ])
    finally:
        _restore_project_file_snapshots(snapshots)


def remove_generated_default_entrypoints(*, had_main: bool, had_widget_test: bool) -> None:
    """Remove only scaffold files created by flutter create, never user files."""
    generated_main = ROOT / "lib/main.dart"
    if not had_main and generated_main.exists():
        generated_main.unlink()
    generated_widget_test = ROOT / "test/widget_test.dart"
    if not had_widget_test and generated_widget_test.exists():
        generated_widget_test.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-host-generation", action="store_true", help="Only apply platform configuration to existing host folders.")
    args = parser.parse_args()

    if not (ROOT / "pubspec.yaml").is_file() or not APP_ENTRYPOINT.is_file():
        parser.error("The project must contain pubspec.yaml and lib/AmitarGalleryPlayer.dart.")

    # Guard the entire operation. The inner Flutter-create guard handles the
    # scaffold command itself; this outer guard also protects both SDK metadata
    # and the checked-in dependency lock from later host-configuration steps.
    project_file_snapshots = _capture_project_file_snapshots()
    try:
        if not args.skip_host_generation:
            if shutil.which("flutter") is None:
                print("ERROR: Flutter SDK is required. Install Flutter 3.47.9 or newer stable and add flutter/bin to PATH.", file=sys.stderr)
                return 2
            had_main = (ROOT / "lib/main.dart").exists()
            had_widget_test = (ROOT / "test/widget_test.dart").exists()
            run_flutter_create_preserving_metadata()
            remove_generated_default_entrypoints(
                had_main=had_main,
                had_widget_test=had_widget_test,
            )
        ensure_android_manifest()
        configure_android_gradle()
        ensure_verified_gradle_wrapper_jar()
        configure_apple_hosts()
        configure_linux_icon()
        missing = [name for name in PLATFORMS.split(",") if not (ROOT / name).is_dir()]
        if missing:
            raise RuntimeError("Platform host generation incomplete: " + ", ".join(missing))
        print("Platform hosts and Android Gradle Wrapper are configured and verified.")
        print("Note: host generation does not install platform SDKs, signing certificates or native build tools.")
        return 0
    finally:
        _restore_project_file_snapshots(project_file_snapshots)


if __name__ == "__main__":
    raise SystemExit(main())
