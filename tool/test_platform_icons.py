"""Tests for cross-platform launcher-icon integrity checks."""
from __future__ import annotations

import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from verify_platform_icons import IconValidationError, verify_platform_icons

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def fake_png(size: int = 64) -> bytes:
    header = struct.pack(">II", size, size) + b"\x08\x06\x00\x00\x00"
    scanline = b"\x00" + (b"\x00\x00\x00\xff" * size)
    pixels = zlib.compress(scanline * size)
    return PNG_SIGNATURE + _png_chunk(b"IHDR", header) + _png_chunk(b"IDAT", pixels) + _png_chunk(b"IEND", b"")


def put_png(root: Path, relative: str, size: int = 64) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(fake_png(size))


class PlatformIconTests(unittest.TestCase):
    def create_complete_fixture(self, root: Path) -> None:
        source_assets = (
            "assets/icons/app-icon-1024.png",
            "assets/icons/ios-app-store-1024.png",
            "assets/icons/ios-dark-transparent-1024.png",
            "assets/icons/android-adaptive-foreground.png",
            "assets/icons/android-adaptive-background.png",
            "assets/icons/android-adaptive-monochrome.png",
            "assets/icons/linux-256.png",
            "assets/icons/linux-512.png",
        )
        for relative in source_assets:
            put_png(root, relative, 1024 if "1024" in relative else 256)
        put_png(root, "linux/runner/resources/app_icon.png", 256)
        put_png(root, "web/icons/Icon-192.png", 192)
        put_png(root, "web/icons/Icon-512.png", 512)
        put_png(root, "web/favicon.png", 32)

        # A valid single-frame 256x256 ICO directory fixture.
        ico = struct.pack("<HHH", 0, 1, 1) + b"\x00\x00\x00\x00\x01\x00\x20\x00" + struct.pack("<II", 4, 22) + b"ICON"
        for relative in ("assets/icons/app-icon.ico", "windows/runner/resources/app_icon.ico"):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(ico)

        for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
            put_png(root, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png", 48)
            put_png(root, f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png", 108)
            put_png(root, f"android/app/src/main/res/mipmap-{density}/ic_launcher_monochrome.png", 108)
        android_res = root / "android/app/src/main/res"
        (android_res / "values").mkdir(parents=True, exist_ok=True)
        (android_res / "values/colors.xml").write_text(
            '<resources><color name="ic_launcher_background">#00000000</color></resources>',
            encoding="utf-8",
        )
        adaptive = android_res / "mipmap-anydpi-v26/ic_launcher.xml"
        adaptive.parent.mkdir(parents=True, exist_ok=True)
        adaptive.write_text(
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
            '<background android:drawable="@color/ic_launcher_background"/>'
            '<foreground android:drawable="@mipmap/ic_launcher_foreground"/>'
            '<monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>'
            '</adaptive-icon>',
            encoding="utf-8",
        )
        manifest = root / "android/app/src/main/AndroidManifest.xml"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:icon="@mipmap/ic_launcher"/></manifest>',
            encoding="utf-8",
        )

        for platform in ("ios", "macos"):
            relative = f"{platform}/Runner/Assets.xcassets/AppIcon.appiconset"
            put_png(root, f"{relative}/icon.png", 1024)
            contents = {"images": [{"filename": "icon.png", "idiom": "universal", "size": "1024x1024"}], "info": {"version": 1, "author": "xcode"}}
            path = root / relative / "Contents.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(contents), encoding="utf-8")

        manifest = {
            "name": "AmitarGalleryPlayer",
            "icons": [
                {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png"},
                {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png"},
            ],
        }
        (root / "web").mkdir(parents=True, exist_ok=True)
        (root / "web/manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def test_all_six_platform_icon_sets_are_verified(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.create_complete_fixture(root)
            result = verify_platform_icons(root)
        self.assertEqual(set(result), {"Android", "iOS", "macOS", "Windows", "Linux", "Web"})
        self.assertGreaterEqual(result["Android"], 9)
        self.assertEqual(result["Windows"], 1)
        self.assertEqual(result["Linux"], 1)
        self.assertGreaterEqual(result["Web"], 3)

    def test_missing_android_adaptive_monochrome_layer_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.create_complete_fixture(root)
            adaptive = root / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
            adaptive.write_text(
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">'
                '<background android:drawable="@color/ic_launcher_background"/>'
                '<foreground android:drawable="@mipmap/ic_launcher_foreground"/>'
                '</adaptive-icon>', encoding="utf-8"
            )
            with self.assertRaisesRegex(IconValidationError, "monochrome"):
                verify_platform_icons(root)

    def test_missing_windows_icon_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.create_complete_fixture(root)
            (root / "windows/runner/resources/app_icon.ico").unlink()
            with self.assertRaisesRegex(IconValidationError, "windows/runner/resources/app_icon.ico"):
                verify_platform_icons(root)

    def test_web_manifest_must_reference_192_and_512_icons(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.create_complete_fixture(root)
            manifest_path = root / "web/manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["icons"] = [manifest["icons"][0]]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(IconValidationError, "512x512"):
                verify_platform_icons(root)


if __name__ == "__main__":
    unittest.main()
