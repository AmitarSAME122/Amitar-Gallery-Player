"""Regression tests for the transparent user-supplied brand asset pipeline."""
from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

from PIL import Image

import generate_brand_assets as branding


class TransparentBrandAssetTests(unittest.TestCase):
    def test_user_source_and_in_app_logo_are_byte_identical(self) -> None:
        source = branding.SOURCE
        app_logo = branding.APP_LOGO
        self.assertTrue(source.is_file())
        self.assertTrue(app_logo.is_file())
        self.assertEqual(
            hashlib.sha256(source.read_bytes()).hexdigest(),
            hashlib.sha256(app_logo.read_bytes()).hexdigest(),
        )

    def test_source_is_rgba_with_transparent_and_semitransparent_pixels(self) -> None:
        with Image.open(branding.SOURCE) as image:
            self.assertEqual(image.mode, "RGBA")
            alpha = image.getchannel("A")
            self.assertEqual(alpha.getextrema()[0], 0)
            self.assertLess(alpha.getextrema()[1], 256)
            self.assertTrue(any(0 < value < 255 for value in alpha.get_flattened_data()))

    def test_make_icon_preserves_alpha_without_cropping_or_flattening(self) -> None:
        with Image.open(branding.SOURCE) as source:
            source = source.convert("RGBA")
            icon = branding.make_icon(source, 1024)
            expected = source.resize((1024, 1024), Image.Resampling.LANCZOS)
        self.assertEqual(icon.mode, "RGBA")
        self.assertEqual(icon.size, (1024, 1024))
        self.assertEqual(icon.tobytes(), expected.tobytes())
        self.assertLess(icon.getchannel("A").getextrema()[0], 255)

    def test_color_outputs_and_android_foreground_retain_alpha(self) -> None:
        paths = [
            branding.ICON_DIR / "app-icon-1024.png",
            branding.ICON_DIR / "android-adaptive-foreground.png",
            branding.ICON_DIR / "icon-512.png",
            branding.ICON_DIR / "linux-512.png",
            branding.PRESENTATION / "AmitarGalleryPlayer_Icon_1024.png",
        ]
        for path in paths:
            with self.subTest(path=path.name), Image.open(path) as image:
                self.assertEqual(image.mode, "RGBA")
                self.assertLess(image.getchannel("A").getextrema()[0], 255)

    def test_adaptive_background_is_fully_transparent(self) -> None:
        with Image.open(branding.ICON_DIR / "android-adaptive-background.png") as image:
            self.assertEqual(image.mode, "RGBA")
            self.assertEqual(image.getchannel("A").getextrema(), (0, 0))

    def test_ios_store_icon_is_separate_and_fully_opaque(self) -> None:
        with Image.open(branding.ICON_DIR / "ios-app-store-1024.png") as image:
            self.assertEqual(image.size, (1024, 1024))
            self.assertEqual(image.mode, "RGB")
        with Image.open(branding.ICON_DIR / "ios-dark-transparent-1024.png") as image:
            self.assertEqual(image.mode, "RGBA")
            self.assertEqual(image.getchannel("A").getextrema()[0], 0)

    def test_windows_ico_preserves_alpha(self) -> None:
        with Image.open(branding.ICON_DIR / "app-icon.ico") as image:
            rgba = image.convert("RGBA")
            self.assertLess(rgba.getchannel("A").getextrema()[0], 255)

    def test_pubspec_uses_transparent_adaptive_background_and_ios_variant(self) -> None:
        pubspec = (branding.ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("adaptive_icon_background: assets/icons/android-adaptive-background.png", pubspec)
        self.assertIn("image_path_ios: assets/icons/ios-app-store-1024.png", pubspec)
        self.assertIn("image_path_ios_dark_transparent: assets/icons/ios-dark-transparent-1024.png", pubspec)
        self.assertIn("adaptive_icon_foreground_inset: 0", pubspec)

    def test_in_app_logo_widgets_do_not_add_gradient_tiles(self) -> None:
        dart = (branding.ROOT / "lib/AmitarGalleryPlayer.dart").read_text(encoding="utf-8")
        import re
        logo_positions = [match.start() for match in re.finditer(r"'assets/AmitarGalleryPlayer\.png'", dart)]
        self.assertEqual(len(logo_positions), 2)
        for position in logo_positions:
            self.assertIn("fit: BoxFit.contain", dart[position:position + 140])
        self.assertNotIn("ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.asset('assets/AmitarGalleryPlayer.png'", dart)


if __name__ == "__main__":
    unittest.main()
