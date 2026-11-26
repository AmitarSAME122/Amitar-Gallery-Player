"""Regression tests for source and release tag identity."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_release_version


class ReleaseVersionTests(unittest.TestCase):
    def _write_project(self, root: Path, dart_version: str = "1.0.0", installer_version: str = "1.0.0") -> None:
        (root / "pubspec.yaml").write_text("name: test\nversion: 1.0.0+1\n", encoding="utf-8")
        dart = root / "lib/AmitarGalleryPlayer.dart"
        dart.parent.mkdir(parents=True)
        dart.write_text(f"const String appVersion = '{dart_version}';\n", encoding="utf-8")
        installer = root / "tool/installer/AmitarGalleryPlayer.iss"
        installer.parent.mkdir(parents=True)
        installer.write_text(f'#define AppVersion "{installer_version}"\n', encoding="utf-8")

    def test_version_and_tag_match(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._write_project(root)
            with mock.patch.object(check_release_version, "ROOT", root), mock.patch("sys.argv", ["check_release_version.py", "--tag", "v1.0.0"]):
                self.assertEqual(check_release_version.main(), 0)

    def test_version_drift_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._write_project(root, dart_version="1.0.1")
            with mock.patch.object(check_release_version, "ROOT", root), mock.patch("sys.argv", ["check_release_version.py"]):
                with self.assertRaises(RuntimeError):
                    check_release_version.main()

    def test_tag_drift_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._write_project(root)
            with mock.patch.object(check_release_version, "ROOT", root), mock.patch("sys.argv", ["check_release_version.py", "--tag", "v1.0.1"]):
                with self.assertRaises(RuntimeError):
                    check_release_version.main()


if __name__ == "__main__":
    unittest.main()
