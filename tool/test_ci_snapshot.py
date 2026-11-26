"""Regression tests for safely sharing one analyzed source across CI jobs."""
from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load_helper(name: str):
    path = ROOT / "tool" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load helper: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


collect_module = _load_helper("collect_ci_snapshot")
apply_module = _load_helper("apply_ci_snapshot")


class CiSnapshotTests(unittest.TestCase):
    def _git(self, root: Path, *args: str) -> None:
        subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)

    def _make_repo(self, root: Path) -> None:
        self._git(root, "init", "-q")
        self._git(root, "config", "user.name", "CI Snapshot Test")
        self._git(root, "config", "user.email", "ci-snapshot@example.invalid")
        (root / "lib").mkdir()
        (root / "test").mkdir()
        (root / "pubspec.yaml").write_text("name: fixture\n", encoding="utf-8")
        (root / "analysis_options.yaml").write_text("linter:\n  rules: []\n", encoding="utf-8")
        (root / "lib/app.dart").write_text("void main() {}\n", encoding="utf-8")
        (root / "test/app_test.dart").write_text("// initial test\n", encoding="utf-8")
        self._git(root, "add", ".")
        self._git(root, "commit", "-m", "initial")

    def test_collects_only_allowed_tracked_and_untracked_quality_changes(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "repo"
            output = Path(folder) / "snapshot"
            root.mkdir()
            self._make_repo(root)
            (root / "lib/app.dart").write_text("void main() { /* formatted */ }\n", encoding="utf-8")
            (root / "pubspec.yaml").write_text("name: fixture\ndescription: changed\n", encoding="utf-8")
            (root / "test/new_test.dart").write_text("// generated test\n", encoding="utf-8")
            (root / "README.md").write_text("must not be included\n", encoding="utf-8")

            files = collect_module.collect(root, output)
            self.assertEqual(
                files,
                ["lib/app.dart", "pubspec.yaml", "test/new_test.dart"],
            )
            self.assertEqual(
                (output / "changed-files.txt").read_text(encoding="utf-8").splitlines(),
                files,
            )
            self.assertFalse((output / "README.md").exists())

    def test_apply_snapshot_copies_exact_sources_and_resolved_lock(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            root = base / "build-checkout"
            artifact = base / "quality-artifact"
            lock_dir = base / "lock-artifact"
            root.mkdir()
            artifact.mkdir()
            lock_dir.mkdir()
            (root / "lib").mkdir()
            (root / "lib/app.dart").write_text("old source\n", encoding="utf-8")
            (artifact / "lib").mkdir()
            (artifact / "lib/app.dart").write_text("tested source\n", encoding="utf-8")
            (artifact / "changed-files.txt").write_text("lib/app.dart\n", encoding="utf-8")
            (lock_dir / "pubspec.lock").write_text("resolved lock\n", encoding="utf-8")

            applied = apply_module.apply_snapshot(root, artifact, lock_dir / "pubspec.lock")
            self.assertEqual(applied, ["lib/app.dart", "pubspec.lock"])
            self.assertEqual((root / "lib/app.dart").read_text(encoding="utf-8"), "tested source\n")
            self.assertEqual((root / "pubspec.lock").read_text(encoding="utf-8"), "resolved lock\n")

    def test_rejects_path_traversal_and_duplicate_manifest_entries(self) -> None:
        for manifest_text in ("../escape.dart\n", "lib/app.dart\nlib/app.dart\n"):
            with self.subTest(manifest=manifest_text), tempfile.TemporaryDirectory() as folder:
                base = Path(folder)
                root = base / "root"
                artifact = base / "artifact"
                root.mkdir()
                artifact.mkdir()
                (artifact / "changed-files.txt").write_text(manifest_text, encoding="utf-8")
                with self.assertRaises(ValueError):
                    apply_module.apply_snapshot(root, artifact)

    def test_rejects_symlinked_snapshot_source(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            root = base / "root"
            artifact = base / "artifact"
            root.mkdir()
            artifact.mkdir()
            outside = base / "outside.dart"
            outside.write_text("not trusted\n", encoding="utf-8")
            (artifact / "lib").mkdir()
            (artifact / "lib/app.dart").symlink_to(outside)
            (artifact / "changed-files.txt").write_text("lib/app.dart\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                apply_module.apply_snapshot(root, artifact)

    def test_collector_rejects_symlinked_output_directory(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            root = base / "repo"
            actual = base / "actual"
            output_link = base / "out-link"
            root.mkdir()
            actual.mkdir()
            self._make_repo(root)
            output_link.symlink_to(actual, target_is_directory=True)
            with self.assertRaises(ValueError):
                collect_module.collect(root, output_link)

    def test_collector_rejects_symlinked_source_parent(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            root = base / "repo"
            outside = base / "outside"
            output = base / "snapshot"
            root.mkdir()
            outside.mkdir()
            self._make_repo(root)
            (outside / "app.dart").write_text("changed through symlink\n", encoding="utf-8")
            (root / "lib").rename(root / "lib-real")
            (root / "lib").symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                collect_module._reject_symlink_components(root, root / "lib/app.dart")


if __name__ == "__main__":
    unittest.main()
