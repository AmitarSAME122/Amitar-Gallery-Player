"""Unit tests for platform bootstrap configuration; no Flutter SDK required."""
from __future__ import annotations

import hashlib
import io
import plistlib
import tempfile
import unittest
import zipfile
import urllib.error
from pathlib import Path
from unittest import mock
import xml.etree.ElementTree as ET

import bootstrap_platforms


class BootstrapConfigurationTests(unittest.TestCase):
    def test_android_permissions_are_scoped_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            manifest = root / "android/app/src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '  <application android:label="old-name" />\n'
                '</manifest>\n',
                encoding="utf-8",
            )
            with mock.patch.object(bootstrap_platforms, "ROOT", root):
                bootstrap_platforms.ensure_android_manifest()
                first = manifest.read_text(encoding="utf-8")
                bootstrap_platforms.ensure_android_manifest()
                second = manifest.read_text(encoding="utf-8")

            self.assertEqual(first, second)
            ET.fromstring(second)
            self.assertIn('android:label="AmitarGalleryPlayer"', second)
            self.assertIn('android.permission.READ_MEDIA_VISUAL_USER_SELECTED', second)
            self.assertIn('android:maxSdkVersion="32"', second)
            self.assertNotIn('android.permission.MANAGE_EXTERNAL_STORAGE', second)

    def test_android_gradle_stack_is_correct_and_bootstrap_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old_main = root / "android/app/src/main/kotlin/com/example/amitar_gallery_player/MainActivity.kt"
            old_main.parent.mkdir(parents=True)
            old_main.write_text(
                "package com.example.amitar_gallery_player\n\n"
                "import io.flutter.embedding.android.FlutterActivity\n\n"
                "class MainActivity : FlutterActivity()\n",
                encoding="utf-8",
            )
            with mock.patch.object(bootstrap_platforms, "ROOT", root):
                bootstrap_platforms.configure_android_gradle()
                first = (root / "android/settings.gradle.kts").read_text(encoding="utf-8")
                bootstrap_platforms.configure_android_gradle()
                second = (root / "android/settings.gradle.kts").read_text(encoding="utf-8")

            self.assertEqual(first, second)
            app = (root / "android/app/build.gradle.kts").read_text(encoding="utf-8")
            wrapper = (root / "android/gradle/wrapper/gradle-wrapper.properties").read_text(encoding="utf-8")
            self.assertIn('includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")', first)
            self.assertIn('id("dev.flutter.flutter-plugin-loader")', first)
            self.assertNotIn('id("dev.flutter.flutter-plugin-loader")', app)
            self.assertIn("compilerOptions", app)
            self.assertIn("JvmTarget.JVM_17", app)
            self.assertNotIn("kotlinOptions", app)
            android_section = app.split("android {", 1)[1].split("\n}\n\nkotlin {", 1)[0]
            self.assertNotIn("compilerOptions", android_section)
            self.assertIn("\n}\n\nkotlin {\n    compilerOptions", app)
            self.assertIn('id("dev.flutter.flutter-gradle-plugin")', app)
            self.assertIn('version "8.13.2"', first)
            self.assertIn('version "2.4.21"', first)
            self.assertIn('requested.id.namespace == "com.android"', first)
            self.assertIn('useModule("com.android.tools.build:gradle:${requested.version}")', first)
            self.assertIn('System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")', first)
            self.assertIn('google()', first)
            self.assertLess(first.index('maven {'), first.index('google()'))
            root_build = (root / "android/build.gradle.kts").read_text(encoding="utf-8")
            self.assertIn('System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")', root_build)
            self.assertIn('google()', root_build)
            self.assertIn('distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.6-bin.zip', wrapper)
            self.assertIn('distributionSha256Sum=7988ed071b2a07900e2ec715fca15c6ab72bce6db433af301fa7fa7e9407bd24', wrapper)
            self.assertIn('applicationId = "com.amitar.amitar_gallery_player"', app)
            self.assertTrue((root / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt").is_file())
            self.assertFalse(old_main.exists())
            self.assertNotIn('maven.aliyun.com', first + app)
            self.assertNotIn('jitpack.io', first + app)


    def test_unix_gradle_wrapper_execute_bit_is_restored(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wrapper = root / "android/gradlew"
            wrapper.parent.mkdir(parents=True)
            wrapper.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            wrapper.chmod(0o644)
            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms.sys, "platform", "linux"):
                bootstrap_platforms.ensure_unix_gradle_wrapper_executable()
            self.assertTrue(wrapper.stat().st_mode & 0o100)

    def test_android_maven_diagnostic_checks_real_agp_module_not_only_marker(self) -> None:
        script = (bootstrap_platforms.ROOT / "tool/check_android_maven_windows.ps1").read_text(encoding="utf-8")
        self.assertIn("https://dl.google.com/dl/android/maven2", script)
        self.assertIn("com/android/tools/build/gradle/$agpVersion/gradle-$agpVersion.pom", script)
        self.assertIn("com/android/application/com.android.application.gradle.plugin", script)
        self.assertIn("AMITAR_GOOGLE_MAVEN_MIRROR", script)
        self.assertIn("must use HTTPS", script)
        self.assertTrue((bootstrap_platforms.ROOT / "tool/check_android_maven_windows.bat").is_file())

    @staticmethod
    def _make_wrapper_jar_fixture() -> bytes:
        payload_buffer = io.BytesIO()
        with zipfile.ZipFile(payload_buffer, "w") as archive:
            archive.writestr("org/gradle/wrapper/GradleWrapperMain.class", b"fixture")
        return payload_buffer.getvalue()

    class FakeResponse(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, traceback):
            self.close()

    def test_gradle_wrapper_download_is_sha256_verified_before_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wrapper = root / "android/gradle/wrapper/gradle-wrapper.jar"
            wrapper.parent.mkdir(parents=True)
            old_bytes = b"untrusted-old-wrapper"
            wrapper.write_bytes(old_bytes)

            payload = self._make_wrapper_jar_fixture()
            expected_hash = hashlib.sha256(payload).hexdigest()

            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "GRADLE_WRAPPER_SHA256", expected_hash), \
                 mock.patch.object(
                     bootstrap_platforms.urllib.request,
                     "urlopen",
                     return_value=self.FakeResponse(payload),
                 ) as urlopen:
                bootstrap_platforms.ensure_verified_gradle_wrapper_jar()

            self.assertEqual(wrapper.read_bytes(), payload)
            self.assertEqual(urlopen.call_args.args[0].full_url, bootstrap_platforms.GRADLE_WRAPPER_URL)
            self.assertFalse(wrapper.with_name(wrapper.name + ".download").exists())

    def test_gradle_wrapper_download_retries_transient_network_failure(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wrapper = root / "android/gradle/wrapper/gradle-wrapper.jar"
            payload = self._make_wrapper_jar_fixture()
            expected_hash = hashlib.sha256(payload).hexdigest()

            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "GRADLE_WRAPPER_SHA256", expected_hash), \
                 mock.patch.object(
                     bootstrap_platforms.urllib.request,
                     "urlopen",
                     side_effect=[
                         urllib.error.URLError("temporary DNS failure"),
                         self.FakeResponse(payload),
                     ],
                 ) as urlopen, \
                 mock.patch.object(bootstrap_platforms.time, "sleep") as sleep:
                bootstrap_platforms.ensure_verified_gradle_wrapper_jar()

            self.assertEqual(urlopen.call_count, 2)
            sleep.assert_called_once_with(1)
            self.assertEqual(wrapper.read_bytes(), payload)

    def test_gradle_wrapper_url_is_pinned_to_the_checksum_matching_gradle_commit(self) -> None:
        self.assertEqual(bootstrap_platforms.GRADLE_WRAPPER_SOURCE_COMMIT, "c27417f")
        self.assertIn(
            "/gradle/gradle/c27417f/gradle/wrapper/gradle-wrapper.jar",
            bootstrap_platforms.GRADLE_WRAPPER_URL,
        )

    def test_verified_local_gradle_wrapper_is_reused_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wrapper = root / "android/gradle/wrapper/gradle-wrapper.jar"
            wrapper.parent.mkdir(parents=True)
            verified_payload = self._make_wrapper_jar_fixture()
            wrapper.write_bytes(verified_payload)
            expected_hash = hashlib.sha256(verified_payload).hexdigest()
            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "GRADLE_WRAPPER_SHA256", expected_hash), \
                 mock.patch.object(bootstrap_platforms.urllib.request, "urlopen") as download:
                bootstrap_platforms.ensure_verified_gradle_wrapper_jar()
            download.assert_not_called()
            self.assertEqual(wrapper.read_bytes(), verified_payload)

    def test_gradle_wrapper_hash_mismatch_preserves_existing_file_and_fails(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wrapper = root / "android/gradle/wrapper/gradle-wrapper.jar"
            wrapper.parent.mkdir(parents=True)
            old = b"untrusted-old-wrapper"
            wrapper.write_bytes(old)
            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "GRADLE_WRAPPER_SHA256", "0" * 64), \
                 mock.patch.object(bootstrap_platforms.urllib.request, "urlopen", return_value=io.BytesIO(b"tampered")):
                with self.assertRaisesRegex(RuntimeError, "failed SHA-256 verification"):
                    bootstrap_platforms.ensure_verified_gradle_wrapper_jar()
            self.assertEqual(wrapper.read_bytes(), old)
            self.assertFalse(wrapper.with_name(wrapper.name + ".download").exists())

    def test_apple_entitlements_use_documented_photos_access_and_preserve_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            entitlements = Path(folder) / "Release.entitlements"
            with entitlements.open("wb") as handle:
                plistlib.dump({
                    "com.apple.security.app-sandbox": True,
                    "com.apple.security.network.server": True,
                }, handle)

            bootstrap_platforms.update_entitlements(entitlements)
            with entitlements.open("rb") as handle:
                result = plistlib.load(handle)

            self.assertTrue(result["com.apple.security.app-sandbox"])
            self.assertTrue(result["com.apple.security.network.server"])
            self.assertTrue(result["com.apple.security.network.client"])
            self.assertTrue(result["com.apple.security.files.user-selected.read-write"])
            self.assertTrue(result["com.apple.security.personal-information.photos-library"])
            self.assertNotIn("com.apple.security.assets.photos.read-write", result)

    def test_plist_and_deployment_target_updates(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            plist_path = root / "Info.plist"
            with plist_path.open("wb") as handle:
                plistlib.dump({"CFBundleName": "Runner"}, handle)
            bootstrap_platforms.update_plist(plist_path, {
                "CFBundleDisplayName": "AmitarGalleryPlayer",
                "NSPhotoLibraryUsageDescription": "Photos access is user-authorized.",
            })
            with plist_path.open("rb") as handle:
                plist_data = plistlib.load(handle)
            self.assertEqual(plist_data["CFBundleDisplayName"], "AmitarGalleryPlayer")

            project = root / "project.pbxproj"
            project.write_text(
                "IPHONEOS_DEPLOYMENT_TARGET = 13.0;\nMACOSX_DEPLOYMENT_TARGET = 10.15;\n",
                encoding="utf-8",
            )
            bootstrap_platforms.set_xcode_deployment_target(project, "IPHONEOS_DEPLOYMENT_TARGET", "15.0")
            bootstrap_platforms.set_xcode_deployment_target(project, "MACOSX_DEPLOYMENT_TARGET", "12.0")
            text = project.read_text(encoding="utf-8")
            self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 15.0;", text)
            self.assertIn("MACOSX_DEPLOYMENT_TARGET = 12.0;", text)


    def test_flutter_create_preserves_tracked_metadata_and_lockfile_on_success(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            metadata = root / ".metadata"
            lockfile = root / "pubspec.lock"
            original = b"tracked flutter metadata\n"
            original_lockfile = b"tracked dependency lock\n"
            activity = root / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt"
            activity.parent.mkdir(parents=True)
            original_activity = b"class MainActivity : FlutterActivity() // custom channel\n"
            activity.write_bytes(original_activity)
            metadata.write_bytes(original)
            lockfile.write_bytes(original_lockfile)

            def fake_run(command: list[str]) -> None:
                self.assertEqual(command[0:2], ["flutter", "create"])
                metadata.write_bytes(b"runner-specific generated metadata\n")
                lockfile.write_bytes(b"rewritten lock by flutter scaffold\n")
                activity.write_bytes(b"class MainActivity : FlutterActivity() // generated default\n")

            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "run", side_effect=fake_run):
                bootstrap_platforms.run_flutter_create_preserving_metadata()

            self.assertEqual(metadata.read_bytes(), original)
            self.assertEqual(lockfile.read_bytes(), original_lockfile)

    def test_flutter_create_restores_tracked_metadata_and_lockfile_when_command_fails(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            metadata = root / ".metadata"
            lockfile = root / "pubspec.lock"
            original = b"tracked flutter metadata\n"
            original_lockfile = b"tracked dependency lock\n"
            activity = root / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt"
            activity.parent.mkdir(parents=True)
            original_activity = b"class MainActivity : FlutterActivity() // custom channel\n"
            activity.write_bytes(original_activity)
            metadata.write_bytes(original)
            lockfile.write_bytes(original_lockfile)

            def fake_run(command: list[str]) -> None:
                metadata.write_bytes(b"partially generated metadata\n")
                lockfile.write_bytes(b"partially rewritten lock\n")
                activity.write_bytes(b"class MainActivity : FlutterActivity() // generated default\n")
                raise RuntimeError("simulated flutter create failure")

            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "run", side_effect=fake_run):
                with self.assertRaisesRegex(RuntimeError, "simulated flutter create failure"):
                    bootstrap_platforms.run_flutter_create_preserving_metadata()

            self.assertEqual(metadata.read_bytes(), original)
            self.assertEqual(lockfile.read_bytes(), original_lockfile)


    def test_main_keeps_new_android_activity_when_no_activity_existed_before_bootstrap(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "pubspec.yaml").write_text("name: fixture\n", encoding="utf-8")
            app = root / "lib/AmitarGalleryPlayer.dart"
            app.parent.mkdir(parents=True)
            app.write_text("// fixture\n", encoding="utf-8")
            for platform in bootstrap_platforms.PLATFORMS.split(","):
                (root / platform).mkdir(parents=True, exist_ok=True)

            configure_android = bootstrap_platforms.configure_android_gradle
            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "APP_ENTRYPOINT", app), \
                 mock.patch.object(bootstrap_platforms.shutil, "which", return_value="/usr/bin/flutter"), \
                 mock.patch.object(bootstrap_platforms.sys, "argv", ["bootstrap_platforms.py"]), \
                 mock.patch.object(bootstrap_platforms, "run_flutter_create_preserving_metadata"), \
                 mock.patch.object(bootstrap_platforms, "remove_generated_default_entrypoints"), \
                 mock.patch.object(bootstrap_platforms, "ensure_android_manifest"), \
                 mock.patch.object(bootstrap_platforms, "configure_android_gradle", side_effect=configure_android), \
                 mock.patch.object(bootstrap_platforms, "ensure_verified_gradle_wrapper_jar"), \
                 mock.patch.object(bootstrap_platforms, "ensure_unix_gradle_wrapper_executable"), \
                 mock.patch.object(bootstrap_platforms, "configure_apple_hosts"), \
                 mock.patch.object(bootstrap_platforms, "configure_linux_icon"):
                self.assertEqual(bootstrap_platforms.main(), 0)

            activity = root / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt"
            self.assertTrue(activity.is_file())
            self.assertIn("class MainActivity : FlutterActivity()", activity.read_text(encoding="utf-8"))

    def test_main_restores_metadata_and_lockfile_after_all_bootstrap_stages(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "pubspec.yaml").write_text("name: fixture\n", encoding="utf-8")
            app = root / "lib/AmitarGalleryPlayer.dart"
            app.parent.mkdir(parents=True)
            app.write_text("// fixture\n", encoding="utf-8")
            metadata = root / ".metadata"
            lockfile = root / "pubspec.lock"
            original = b"tracked metadata before complete bootstrap\n"
            original_lockfile = b"tracked lock before complete bootstrap\n"
            metadata.write_bytes(original)
            lockfile.write_bytes(original_lockfile)
            for platform in bootstrap_platforms.PLATFORMS.split(","):
                (root / platform).mkdir(parents=True, exist_ok=True)

            def mutate_metadata() -> None:
                metadata.write_bytes(b"metadata changed by a later platform stage\n")
                lockfile.write_bytes(b"lock changed by a later platform stage\n")

            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "APP_ENTRYPOINT", app), \
                 mock.patch.object(bootstrap_platforms.shutil, "which", return_value="/usr/bin/flutter"), \
                 mock.patch.object(bootstrap_platforms.sys, "argv", ["bootstrap_platforms.py"]), \
                 mock.patch.object(bootstrap_platforms, "run_flutter_create_preserving_metadata"), \
                 mock.patch.object(bootstrap_platforms, "remove_generated_default_entrypoints"), \
                 mock.patch.object(bootstrap_platforms, "ensure_android_manifest"), \
                 mock.patch.object(bootstrap_platforms, "configure_android_gradle"), \
                 mock.patch.object(bootstrap_platforms, "ensure_verified_gradle_wrapper_jar"), \
                 mock.patch.object(bootstrap_platforms, "ensure_unix_gradle_wrapper_executable"), \
                 mock.patch.object(bootstrap_platforms, "configure_apple_hosts"), \
                 mock.patch.object(bootstrap_platforms, "configure_linux_icon", side_effect=mutate_metadata):
                self.assertEqual(bootstrap_platforms.main(), 0)

            self.assertEqual(metadata.read_bytes(), original)
            self.assertEqual(lockfile.read_bytes(), original_lockfile)

    def test_main_restores_metadata_and_lockfile_when_a_later_bootstrap_stage_fails(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "pubspec.yaml").write_text("name: fixture\n", encoding="utf-8")
            app = root / "lib/AmitarGalleryPlayer.dart"
            app.parent.mkdir(parents=True)
            app.write_text("// fixture\n", encoding="utf-8")
            metadata = root / ".metadata"
            lockfile = root / "pubspec.lock"
            original = b"tracked metadata before failing bootstrap\n"
            original_lockfile = b"tracked lock before failing bootstrap\n"
            metadata.write_bytes(original)
            lockfile.write_bytes(original_lockfile)
            for platform in bootstrap_platforms.PLATFORMS.split(","):
                (root / platform).mkdir(parents=True, exist_ok=True)

            def mutate_then_fail() -> None:
                metadata.write_bytes(b"partially changed metadata\n")
                lockfile.write_bytes(b"partially changed dependency lock\n")
                raise RuntimeError("simulated later platform configuration failure")

            with mock.patch.object(bootstrap_platforms, "ROOT", root), \
                 mock.patch.object(bootstrap_platforms, "APP_ENTRYPOINT", app), \
                 mock.patch.object(bootstrap_platforms.shutil, "which", return_value="/usr/bin/flutter"), \
                 mock.patch.object(bootstrap_platforms.sys, "argv", ["bootstrap_platforms.py"]), \
                 mock.patch.object(bootstrap_platforms, "run_flutter_create_preserving_metadata"), \
                 mock.patch.object(bootstrap_platforms, "remove_generated_default_entrypoints"), \
                 mock.patch.object(bootstrap_platforms, "ensure_android_manifest"), \
                 mock.patch.object(bootstrap_platforms, "configure_android_gradle"), \
                 mock.patch.object(bootstrap_platforms, "ensure_verified_gradle_wrapper_jar"), \
                 mock.patch.object(bootstrap_platforms, "ensure_unix_gradle_wrapper_executable"), \
                 mock.patch.object(bootstrap_platforms, "configure_apple_hosts"), \
                 mock.patch.object(bootstrap_platforms, "configure_linux_icon", side_effect=mutate_then_fail):
                with self.assertRaisesRegex(RuntimeError, "simulated later platform configuration failure"):
                    bootstrap_platforms.main()

            self.assertEqual(metadata.read_bytes(), original)
            self.assertEqual(lockfile.read_bytes(), original_lockfile)

    def test_generated_main_entrypoint_is_removed_but_user_main_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with mock.patch.object(bootstrap_platforms, "ROOT", root):
                generated = root / "lib/main.dart"
                generated.parent.mkdir(parents=True)
                generated.write_text("// generated scaffold", encoding="utf-8")
                bootstrap_platforms.remove_generated_default_entrypoints(
                    had_main=False,
                    had_widget_test=True,
                )
                self.assertFalse(generated.exists())

                generated.write_text("// user maintained source", encoding="utf-8")
                bootstrap_platforms.remove_generated_default_entrypoints(
                    had_main=True,
                    had_widget_test=True,
                )
                self.assertTrue(generated.exists())

    def test_generated_widget_test_is_removed_only_when_created_by_scaffold(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with mock.patch.object(bootstrap_platforms, "ROOT", root):
                generated = root / "test/widget_test.dart"
                generated.parent.mkdir(parents=True)
                generated.write_text("// generated test", encoding="utf-8")
                bootstrap_platforms.remove_generated_default_entrypoints(
                    had_main=True,
                    had_widget_test=False,
                )
                self.assertFalse(generated.exists())

                generated.write_text("// user maintained test", encoding="utf-8")
                bootstrap_platforms.remove_generated_default_entrypoints(
                    had_main=True,
                    had_widget_test=True,
                )
                self.assertTrue(generated.exists())

    def test_linux_icon_is_installed_and_wired_to_the_gtk_window(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "assets/icons/linux-256.png"
            source.parent.mkdir(parents=True)
            source.write_bytes(b"png-icon-fixture")
            runner_dir = root / "linux/runner"
            runner_dir.mkdir(parents=True)
            runner = runner_dir / "my_application.cc"
            runner.write_text(
                'static void activate() {\n'
                '  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(nullptr));\n'
                '  gtk_window_set_default_size(window, 1280, 720);\n'
                '}\n', encoding="utf-8"
            )
            with mock.patch.object(bootstrap_platforms, "ROOT", root):
                bootstrap_platforms.configure_linux_icon()
                bootstrap_platforms.configure_linux_icon()
            destination = root / "linux/runner/resources/app_icon.png"
            self.assertEqual(destination.read_bytes(), b"png-icon-fixture")
            result = runner.read_text(encoding="utf-8")
            self.assertIn("AmitarGalleryPlayer Linux window icon", result)
            self.assertIn('g_file_read_link("/proc/self/exe", NULL)', result)
            self.assertIn('"linux-256.png"', result)
            self.assertEqual(result.count("AmitarGalleryPlayer Linux window icon"), 1)



if __name__ == "__main__":
    unittest.main()
