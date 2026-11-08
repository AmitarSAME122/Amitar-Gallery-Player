"""Static invariants for release-sensitive application and CI paths."""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "lib/AmitarGalleryPlayer.dart"


class ProjectInvariantTests(unittest.TestCase):
    def test_renamed_entrypoint_is_the_only_app_source_entrypoint(self) -> None:
        self.assertTrue(SOURCE.is_file())
        self.assertFalse((ROOT / "lib/main.dart").exists())
        build = (ROOT / "tool/build.py").read_text(encoding="utf-8")
        self.assertIn('ENTRYPOINT = "lib/AmitarGalleryPlayer.dart"', build)
        for relative in ("tool/bootstrap_platforms.py", "tool/check_release_version.py", "tool/finalize_artifacts.py"):
            self.assertIn("lib/AmitarGalleryPlayer.dart", (ROOT / relative).read_text(encoding="utf-8"))
        old_entrypoint_name = "AmitarGallery" + "Play.dart"
        self.assertNotIn(old_entrypoint_name, "\n".join(
            path.read_text(encoding="utf-8")
            for path in ROOT.rglob("*")
            if path.is_file() and path != Path(__file__)
            and path.suffix in {".py", ".md", ".kts", ".yaml", ".yml", ".txt"}
            and "__pycache__" not in path.parts
        ))


    def test_android_gradle_plugins_and_versions_are_consistent(self) -> None:
        settings = (ROOT / "android/settings.gradle.kts").read_text(encoding="utf-8")
        app = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
        wrapper = (ROOT / "android/gradle/wrapper/gradle-wrapper.properties").read_text(encoding="utf-8")
        self.assertIn('id("dev.flutter.flutter-plugin-loader")', settings)
        self.assertNotIn('id("dev.flutter.flutter-plugin-loader")', app)
        self.assertIn('id("dev.flutter.flutter-gradle-plugin")', app)
        self.assertIn("compilerOptions", app)
        self.assertIn("JvmTarget.JVM_17", app)
        self.assertNotIn("kotlinOptions", app)
        android_section = app.split("android {", 1)[1].split("\n}\n\nkotlin {", 1)[0]
        self.assertNotIn("compilerOptions", android_section)
        self.assertIn("\n}\n\nkotlin {\n    compilerOptions", app)
        self.assertIn('version "8.13.2"', settings)
        self.assertIn('version "2.4.21"', settings)
        self.assertIn('requested.id.namespace == "com.android"', settings)
        self.assertIn('useModule("com.android.tools.build:gradle:${requested.version}")', settings)
        self.assertIn('System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")', settings)
        self.assertIn('google()', settings)
        self.assertIn('System.getenv("AMITAR_GOOGLE_MAVEN_MIRROR")', (ROOT / "android/build.gradle.kts").read_text(encoding="utf-8"))
        diagnostic = (ROOT / "tool/check_android_maven_windows.ps1").read_text(encoding="utf-8")
        self.assertIn("com/android/tools/build/gradle/$agpVersion/gradle-$agpVersion.pom", diagnostic)
        self.assertIn("gradle-8.14.6-bin.zip", wrapper)
        self.assertIn("distributionSha256Sum=7988ed071b2a07900e2ec715fca15c6ab72bce6db433af301fa7fa7e9407bd24", wrapper)
        bootstrap = (ROOT / "tool/bootstrap_platforms.py").read_text(encoding="utf-8")
        self.assertIn("GRADLE_WRAPPER_SHA256 = \"ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0\"", bootstrap)
        self.assertIn("ensure_verified_gradle_wrapper_jar()", bootstrap)
        self.assertIn("GRADLE_WRAPPER_SOURCE_COMMIT = \"c27417f\"", bootstrap)
        self.assertIn("raw.githubusercontent.com/gradle/gradle/", bootstrap)
        self.assertNotIn("services.gradle.org/distributions/gradle-8.14.6-wrapper.jar", bootstrap)
        build_entry = (ROOT / "tool/build.py").read_text(encoding="utf-8")
        self.assertIn("tool/verify_platform_icons.py", build_entry)
        self.assertLess(build_entry.index("dart\", \"run\", \"flutter_launcher_icons"), build_entry.index("tool/verify_platform_icons.py"))
        self.assertIn("retries=3", wrapper)
        self.assertIn('namespace = "com.amitar.amitar_gallery_player"', app)
        self.assertIn('applicationId = "com.amitar.amitar_gallery_player"', app)
        self.assertNotIn("maven.aliyun.com", settings + app)
        self.assertNotIn("jitpack.io", settings + app)

    def test_unix_gradle_wrapper_keeps_its_executable_bit(self) -> None:
        import os
        wrapper = ROOT / "android/gradlew"
        self.assertTrue(wrapper.is_file())
        self.assertTrue(os.access(wrapper, os.X_OK), "android/gradlew must be executable on Unix hosts")

    def test_android_build_refuses_missing_or_unverified_gradle_wrapper(self) -> None:
        build = (ROOT / "tool/build.py").read_text(encoding="utf-8")
        self.assertIn("def verify_android_gradle_wrapper()", build)
        self.assertIn("GRADLE_WRAPPER_SHA256 = \"ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0\"", build)
        self.assertIn("verify_android_gradle_wrapper()", build)
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("android/gradle/wrapper/gradle-wrapper.jar", gitignore)


    def test_android_jdk_is_pinned_and_setup_is_documented(self) -> None:
        build = (ROOT / "tool/build.py").read_text(encoding="utf-8")
        self.assertIn("def verify_android_java_runtime()", build)
        self.assertIn("verify_android_java_runtime()", build)
        guide = (ROOT / "BUILD_GUIDE_FA.md").read_text(encoding="utf-8")
        self.assertIn("setup_android_jdk_windows.bat -InstallIfMissing", guide)
        self.assertIn("flutter config --jdk-dir", guide)
        script = (ROOT / "tool/setup_android_jdk_windows.ps1").read_text(encoding="utf-8")
        self.assertIn("flutter doctor -v", script)
        self.assertIn("-eq 17", script)

    def test_ci_android_publisher_signing_is_optional_and_secret_only(self) -> None:
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        for secret in (
            "AMITAR_ANDROID_KEYSTORE_BASE64",
            "AMITAR_ANDROID_STORE_PASSWORD",
            "AMITAR_ANDROID_KEY_PASSWORD",
            "AMITAR_ANDROID_KEY_ALIAS",
        ):
            self.assertIn(secret, workflow)
        self.assertIn("$RUNNER_TEMP/amitar-gallery-player-release.jks", workflow)
        self.assertIn('"$configured" -ne 4', workflow)
        self.assertIn("android/key.properties", workflow)
        guide = (ROOT / "README.fa.md").read_text(encoding="utf-8")
        self.assertIn("AMITAR_ANDROID_KEYSTORE_BASE64", guide)
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("android/key.properties", gitignore)
        self.assertIn("*.jks", gitignore)

    def test_no_personal_android_sdk_path_is_committed(self) -> None:
        import subprocess

        # `flutter create` legitimately generates android/local.properties on a
        # CI runner. Its presence in the working tree is therefore not evidence
        # that a machine-specific SDK path was committed. Check the Git index,
        # which is the property this invariant is intended to protect.
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("android/local.properties", gitignore)
        self.assertIn("android/key.properties", gitignore)

        repository = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if repository.returncode != 0:
            self.skipTest("Git index check requires a Git working tree")

        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", "android/local.properties"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(
            tracked.returncode,
            0,
            "android/local.properties must remain ignored and must never be committed",
        )

    def test_device_scan_has_initialized_memory_budget_and_item_cap(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("Future<void> scanDeviceLibrary()")
        end = source.index("bool get supportsFolderScanning", start)
        scan = source[start:end]
        self.assertRegex(scan, r"var thumbnailBudget = _maxInMemoryThumbnailBytes")
        self.assertIn("processed >= _maxScanItems", scan)
        self.assertIn("if (truncated) break", scan)
        self.assertIn("remaining items were not scanned", scan)

    def test_folder_scan_does_not_follow_symlinks_and_has_memory_budgets(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("Future<void> scanChosenFolder()")
        end = source.index("Future<void> deleteSystemAsset", start)
        scan = source[start:end]
        self.assertIn("followLinks: false", scan)
        self.assertIn("var thumbnailBudget = _maxInMemoryThumbnailBytes", scan)
        self.assertIn("var previewBudget = _maxInMemoryPreviewBytes", scan)
        self.assertIn("discovered >= _maxScanItems", scan)

    def test_mobile_import_stages_streamed_files_and_cleans_failed_staging(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("Future<int> addPickedFiles(")
        end = source.index("String _folderFromPath", start)
        method = source[start:end]
        self.assertIn("await _stagePickedFileOnMobile(file)", method)
        self.assertIn("finally", method)
        self.assertIn("await staged.delete()", method)
        self.assertIn("var thumbnailBudget = _maxInMemoryThumbnailBytes", method)
        self.assertIn("var previewBudget = _maxInMemoryPreviewBytes", method)

    def test_media_kit_video_bundle_is_not_duplicated_with_audio_bundle(self) -> None:
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("media_kit_libs_video:", pubspec)
        self.assertNotIn("media_kit_libs_audio:", pubspec)

    def test_ci_actions_are_pinned_to_verified_patch_tags(self) -> None:
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        for action in (
            "actions/checkout@v7.0.1",
            "actions/setup-java@v6.1.0",
            "actions/upload-artifact@v7.0.2",
            "actions/download-artifact@v8.0.2",
            "subosito/flutter-action@v2.23.0",
        ):
            self.assertIn(action, workflow)
        self.assertNotRegex(workflow, r"actions/(?:checkout|setup-java|upload-artifact|download-artifact)@v\d+\s")


    def test_ci_formatting_is_non_mutating_and_linux_bootstrap_is_not_repeated(self) -> None:
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("dart format --output=none --set-exit-if-changed lib test", workflow)
        self.assertIn("tool/build.py all --skip-bootstrap --skip-checks", workflow)

    def test_ci_triggers_on_project_branch_and_transfers_verified_wrapper(self) -> None:
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("branches: [ Amitar, main, master ]", workflow)
        self.assertEqual(workflow.count("name: agp-gradle-wrapper-8.14.6"), 4)
        self.assertEqual(workflow.count("Download the checksum-verified Gradle Wrapper JAR"), 3)
        self.assertIn("Upload the verified Gradle Wrapper JAR for native build jobs", workflow)
        self.assertIn("path: android/gradle/wrapper/gradle-wrapper.jar", workflow)
        self.assertIn("timeout-minutes: 120", workflow)

    def test_dependabot_covers_pub_and_github_actions(self) -> None:
        config = (ROOT / ".github/dependabot.yml").read_text(encoding="utf-8")
        self.assertIn("package-ecosystem: pub", config)
        self.assertIn("package-ecosystem: github-actions", config)
        self.assertEqual(config.count("interval: monthly"), 2)

    def test_source_checksum_generator_uses_tracked_files_and_excludes_local_android_state(self) -> None:
        generator = (ROOT / "tool/update_source_checksums.py").read_text(encoding="utf-8")
        self.assertIn('["git", "ls-files", "-z"]', generator)
        self.assertIn('"android/local.properties"', generator)
        self.assertIn('"android/key.properties"', generator)
        manifest = (ROOT / "SHA256SUMS.txt").read_text(encoding="utf-8")
        listed_paths = {line.partition("  ")[2] for line in manifest.splitlines()}
        self.assertNotIn("android/local.properties", listed_paths)
        self.assertNotIn("android/key.properties", listed_paths)
        self.assertNotIn("android/gradle/wrapper/gradle-wrapper.jar", listed_paths)

    def test_source_checksum_manifest_verifies_all_listed_files(self) -> None:
        import hashlib

        manifest = ROOT / "SHA256SUMS.txt"
        if not manifest.is_file():
            self.skipTest("Source checksum manifest is not present yet")
        for line in manifest.read_text(encoding="utf-8").splitlines():
            expected, _, relative = line.partition("  ")
            target = ROOT / relative
            self.assertTrue(target.is_file(), relative)
            actual_bytes = target.read_bytes()
            # The source manifest hashes canonical LF text bytes so it remains
            # reproducible on Windows checkouts and Linux/macOS CI runners.
            binary_suffixes = {".png", ".pdf", ".ico", ".jpg", ".jpeg", ".zip", ".aab", ".apk", ".exe", ".dmg", ".deb"}
            if target.suffix.lower() not in binary_suffixes and not target.name.endswith(".tar.gz"):
                actual_bytes = actual_bytes.replace(b"\r\n", b"\n")
            actual = hashlib.sha256(actual_bytes).hexdigest()
            self.assertEqual(actual, expected, relative)


if __name__ == "__main__":
    unittest.main()
