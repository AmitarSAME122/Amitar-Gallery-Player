"""Unit tests for deterministic artifact packaging helpers."""
from __future__ import annotations

import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import build


class BuildPackagingTests(unittest.TestCase):
    def test_zip_tree_preserves_relative_tree_and_verifies(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source"
            (source / "nested").mkdir(parents=True)
            (source / "app.bin").write_bytes(b"binary")
            (source / "nested/data.txt").write_text("hello", encoding="utf-8")
            output = root / "result.zip"

            build.zip_tree(source, output, "AmitarGalleryPlayer")

            with zipfile.ZipFile(output) as archive:
                self.assertEqual(
                    set(archive.namelist()),
                    {
                        "AmitarGalleryPlayer/app.bin",
                        "AmitarGalleryPlayer/nested/data.txt",
                    },
                )
                self.assertEqual(archive.read("AmitarGalleryPlayer/nested/data.txt"), b"hello")

    def test_flutter_build_always_uses_explicit_renamed_entrypoint(self) -> None:
        with mock.patch.object(build, "run") as run:
            build.flutter_build("web", "--release")
        args = run.call_args.args[0]
        self.assertEqual(args[:3], ["flutter", "build", "web"])
        self.assertEqual(args[-2:], ["--target", "lib/AmitarGalleryPlayer.dart"])

    def test_deb_packaging_produces_valid_package_when_dpkg_is_available(self) -> None:
        if not build.shutil.which("dpkg-deb"):
            self.skipTest("dpkg-deb is not installed on this host")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "bundle"
            source.mkdir()
            executable = source / "amitar_gallery_player"
            executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            executable.chmod(0o755)
            icon_root = root / "assets/icons"
            icon_root.mkdir(parents=True)
            (icon_root / "linux-256.png").write_bytes(b"linux-256-icon")
            (icon_root / "linux-512.png").write_bytes(b"linux-512-icon")
            dist = root / "dist"
            dist.mkdir()
            with mock.patch.object(build, "ROOT", root), mock.patch.object(build, "DIST", dist):
                result = build.create_deb(source)

            self.assertIsNotNone(result)
            assert result is not None
            self.assertTrue(result.is_file())
            info = subprocess.run(
                ["dpkg-deb", "--field", str(result), "Package", "Version", "Architecture", "Depends"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.splitlines()
            fields = {line.partition(": ")[0]: line.partition(": ")[2] for line in info}
            self.assertEqual(fields["Package"], "amitar-gallery-player")
            self.assertEqual(fields["Version"], build.APP_VERSION)
            self.assertTrue(fields["Architecture"])
            self.assertIn("libgtk-3-0", fields["Depends"])
            self.assertIn("libmpv2 | libmpv1", fields["Depends"])
            self.assertNotIn("libglib2.0-0", fields["Depends"])  # already pulled by GTK
            extracted = root / "extracted"
            extracted.mkdir()
            subprocess.run(["dpkg-deb", "--extract", str(result), str(extracted)], check=True)
            self.assertEqual(
                (extracted / "usr/share/icons/hicolor/256x256/apps/amitar-gallery-player.png").read_bytes(),
                b"linux-256-icon",
            )
            self.assertEqual(
                (extracted / "usr/share/icons/hicolor/512x512/apps/amitar-gallery-player.png").read_bytes(),
                b"linux-512-icon",
            )
            desktop = (extracted / "usr/share/applications/amitar-gallery-player.desktop").read_text(encoding="utf-8")
            self.assertIn("Name[fa]=آمیتار گالری پلیر", desktop)
            self.assertIn("Icon=amitar-gallery-player", desktop)
            self.assertIn("StartupWMClass=amitar_gallery_player", desktop)


    def test_flutter_android_java_version_parser_handles_java_17_and_25(self) -> None:
        java_17 = "[✓] Android toolchain - develop for Android devices\n    • Java version OpenJDK Runtime Environment (build 17.0.15+6)\n"
        java_25 = "[✓] Android toolchain - develop for Android devices\n    • Java version OpenJDK Runtime Environment (build 25.0.5+8)\n"
        self.assertEqual(build.extract_flutter_android_java_major(java_17), 17)
        self.assertEqual(build.extract_flutter_android_java_major(java_25), 25)
        self.assertIsNone(build.extract_flutter_android_java_major("No Android toolchain details"))

    def test_android_build_preflight_rejects_java_25_with_fix_instructions(self) -> None:
        result = subprocess.CompletedProcess(
            args=["flutter", "doctor", "-v"],
            returncode=0,
            stdout="    • Java version OpenJDK Runtime Environment (build 25.0.5+8)\n",
            stderr="",
        )
        with mock.patch.object(build.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "using Java 25") as error:
                build.verify_android_java_runtime()
        self.assertIn("setup_android_jdk_windows.bat -InstallIfMissing", str(error.exception))

    def test_android_build_preflight_accepts_java_17(self) -> None:
        result = subprocess.CompletedProcess(
            args=["flutter", "doctor", "-v"],
            returncode=0,
            stdout="    • Java version OpenJDK Runtime Environment (build 17.0.15+6)\n",
            stderr="",
        )
        with mock.patch.object(build.subprocess, "run", return_value=result):
            build.verify_android_java_runtime()

    def test_windows_jdk_setup_script_uses_flutter_config_and_verifies_doctor(self) -> None:
        script = (build.ROOT / "tool/setup_android_jdk_windows.ps1").read_text(encoding="utf-8")
        self.assertIn("EclipseAdoptium.Temurin.17.JDK", script)
        self.assertIn('config "--jdk-dir=$selectedJdk"', script)
        self.assertIn("flutter doctor -v", script)
        self.assertIn("SUCCESS: Flutter is configured to use JDK 17", script)
        self.assertTrue((build.ROOT / "tool/setup_android_jdk_windows.bat").is_file())

    def test_ios_manifest_notes_distinguish_exported_ipa_from_unsigned_app(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            signed = build.artifact_notes([root / "Runner.ipa"])
            unsigned = build.artifact_notes([root / "AmitarGalleryPlayer-iOS-unsigned.zip"])
        self.assertTrue(any("IPA was exported" in item for item in signed))
        self.assertFalse(any("unsigned .app archive" in item for item in signed))
        self.assertTrue(any("unsigned .app archive" in item for item in unsigned))
        self.assertFalse(any("IPA was exported" in item for item in unsigned))

    def test_windows_installer_uses_release_version_and_project_icon(self) -> None:
        icon = build.ROOT / "assets/icons/app-icon.ico"
        if not icon.is_file():
            self.skipTest("Project icon was intentionally omitted from this reduced source archive.")
        script = (build.ROOT / "tool/installer/AmitarGalleryPlayer.iss").read_text(encoding="utf-8")
        self.assertIn('#define AppVersion "1.0.0"', script)
        self.assertIn('SetupIconFile={#ProjectRoot}\\assets\\icons\\app-icon.ico', script)
        self.assertTrue(icon.is_file())


if __name__ == "__main__":
    unittest.main()
