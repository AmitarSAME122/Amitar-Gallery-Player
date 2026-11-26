"""Tests for release manifest validation and checksum finalization."""
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import finalize_artifacts


class FinalizeArtifactsTests(unittest.TestCase):
    def _prepare(self, root: Path, filename: str = "AmitarGalleryPlayer-test.zip") -> None:
        (root / "pubspec.yaml").write_text("name: test\nversion: 1.0.0+1\n", encoding="utf-8")
        entrypoint = root / "lib/AmitarGalleryPlayer.dart"
        entrypoint.parent.mkdir(parents=True)
        entrypoint.write_text("// release entrypoint\n", encoding="utf-8")
        dist = root / "dist"
        dist.mkdir()
        artifact = dist / filename
        artifact.write_bytes(b"release-test-binary")
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        manifest = {
            "version": "1.0.0",
            "entrypoint": "lib/AmitarGalleryPlayer.dart",
            "artifacts": [{"file": filename, "bytes": artifact.stat().st_size, "sha256": digest}],
        }
        (dist / "BUILD-MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")
        (dist / "SHA256SUMS.txt").write_text(f"{digest}  {filename}\n", encoding="utf-8")

    def test_finalizer_renames_manifest_and_writes_verified_runner_checksums(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._prepare(root)
            with mock.patch.object(finalize_artifacts, "ROOT", root), mock.patch.object(finalize_artifacts, "DIST", root / "dist"):
                with mock.patch("sys.argv", ["finalize_artifacts.py", "--label", "test-runner"]):
                    self.assertEqual(finalize_artifacts.main(), 0)
            dist = root / "dist"
            self.assertTrue((dist / "BUILD-MANIFEST-test-runner.json").is_file())
            sums = (dist / "SHA256SUMS-test-runner.txt").read_text(encoding="utf-8")
            self.assertIn("AmitarGalleryPlayer-test.zip", sums)
            self.assertIn("BUILD-MANIFEST-test-runner.json", sums)

    def test_finalizer_rejects_path_traversal_artifact_names(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._prepare(root)
            dist = root / "dist"
            manifest_path = dist / "BUILD-MANIFEST.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["artifacts"][0]["file"] = "../escape.zip"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with mock.patch.object(finalize_artifacts, "ROOT", root), mock.patch.object(finalize_artifacts, "DIST", dist):
                with self.assertRaises(RuntimeError):
                    with mock.patch("sys.argv", ["finalize_artifacts.py", "--label", "test-runner"]):
                        finalize_artifacts.main()


if __name__ == "__main__":
    unittest.main()
